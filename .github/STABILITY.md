# Stability & Throughput Improvement Plan

This document covers all planned changes to reduce cutouts and increase throughput
on the DS918+ ZeroTier moon. Nothing here is implemented yet — approve to proceed.

---

## Root Causes of Cutouts (Diagnosed)

| # | Cause | Where |
|---|-------|-------|
| 1 | Missing `NET_RAW` capability | `docker-compose.yml` |
| 2 | ZeroTier port not pinned — can shift after events, breaking NAT hole-punch | `local.conf` (missing) |
| 3 | UDP socket buffers too small — packets silently dropped under load | `docker-compose.yml` sysctls + `install.sh` |
| 4 | conntrack UDP timeout (30s) shorter than ZeroTier keepalive (~25s) — flow expires under jitter | `entrypoint.sh` + `rules.v4` |
| 5 | No container healthcheck — hung daemon not detected, no auto-restart | `docker-compose.yml` |
| 6 | Alpine 3.19 ships old zerotier-one package | `Dockerfile` |
| 7 | ZeroTier picks up Docker internal bridge interfaces as candidate paths, wastes effort | `local.conf` (missing) |

---

## Throughput Bottlenecks (Diagnosed)

| # | Cause | Where |
|---|-------|-------|
| T1 | Default `fq_codel` qdisc on virtual ZT interface — adds bufferbloat latency under load | `entrypoint.sh` (add `tc qdisc` setup) |
| T2 | NIC offload settings not tuned — GRO/GSO/TSO help batch packets on the J3455 CPU | `install.sh` (add `ethtool` calls) |
| T3 | `net.ipv4.udp_mem` ceiling too low for sustained ZeroTier throughput | `install.sh` + compose `sysctls` |
| T4 | No TCP offload for bridged traffic — the J3455 has hardware AES-NI but ZeroTier uses Salsa20 in software; forwarded traffic should bypass unnecessary re-encryption overhead | confirmed limitation, noted only |
| T5 | macvlan adds a virtual switch hop vs host networking | architectural note — workaround: `tc` on the macvlan |

---

## Planned File Changes

### 1. `config/local.conf` — NEW

```json
{
  "settings": {
    "primaryPort": 9993,
    "allowTcpFallbackRelay": true,
    "portMappingEnabled": true,
    "softwareUpdate": "disable",
    "interfacePrefixBlacklist": ["lo", "docker", "br-", "veth", "dummy"]
  }
}
```

| Setting | Effect |
|---------|--------|
| `primaryPort: 9993` | Pins UDP port — prevents random port rotation that breaks NAT traversal and causes cutouts |
| `allowTcpFallbackRelay` | If UDP is blocked or lost, falls back to TCP relay instead of cutting out entirely |
| `portMappingEnabled` | Enables UPnP/NAT-PMP — better automatic hole-punching through the router |
| `softwareUpdate: disable` | Prevents ZeroTier from pulling updates mid-operation (causes a brief daemon restart) |
| `interfacePrefixBlacklist` | Stops ZeroTier wasting path discovery cycles on Docker's internal bridge interfaces |

Mount into container: `-v /volume1/docker/zerotier/local.conf:/var/lib/zerotier-one/local.conf:ro`

---

### 2. `docker-compose.yml` — MODIFY

```yaml
cap_add:
  - NET_ADMIN
  - NET_RAW        # ADD — required for iptables raw table (NOTRACK); prevents TCP stalls
  - SYS_ADMIN

sysctls:           # ADD — larger UDP buffers in-container
  net.core.rmem_max: 26214400         # 25 MB receive buffer (default ~212 KB)
  net.core.wmem_max: 26214400         # 25 MB send buffer
  net.core.netdev_max_backlog: 5000   # queue size before drops under burst traffic
  net.ipv4.udp_rmem_min: 8192
  net.ipv4.udp_wmem_min: 8192

healthcheck:       # ADD — auto-restart if ZeroTier daemon hangs
  test: ["CMD", "zerotier-cli", "status"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 20s

volumes:
  # ADD local.conf mount
  - /volume1/docker/zerotier/local.conf:/var/lib/zerotier-one/local.conf:ro
```

---

### 3. `config/rules.v4` — MODIFY

Add `*raw` table before `*nat` to bypass conntrack for ZeroTier UDP:

```
*raw
-A PREROUTING -p udp --dport 9993 -j NOTRACK
-A OUTPUT -p udp --sport 9993 -j NOTRACK
COMMIT

*nat
-I POSTROUTING -o zt+ -j MASQUERADE
-I POSTROUTING -o eth0 -j MASQUERADE
-I POSTROUTING -o eth1 -j MASQUERADE
COMMIT
```

Why: conntrack default UDP timeout is 30s. ZeroTier keepalive fires ~every 25s.
Under jitter, conntrack expires the entry just before keepalive arrives — brief cutout.
`NOTRACK` removes ZeroTier from conntrack entirely; no expiry possible.

---

### 4. `entrypoint.sh` — MODIFY

**Add after ZeroTier is ready:**

```bash
# Conntrack UDP timeout — belt-and-suspenders alongside NOTRACK in iptables
sysctl -w net.netfilter.nf_conntrack_udp_timeout=300 &>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_udp_timeout_stream=300 &>/dev/null || true

# Throughput: set fq qdisc on ZeroTier interface to reduce bufferbloat
# fq (fair queuing) provides per-flow pacing and keeps latency low under load
ZT_IF=$(ip link show | awk -F': ' '/^[0-9]+: zt/{print $2; exit}')
if [[ -n "$ZT_IF" ]]; then
    tc qdisc replace dev "$ZT_IF" root fq 2>/dev/null || true
    log "Set fq qdisc on $ZT_IF"
fi
```

**Add before `wait $ZT_PID`:**

```bash
# Log active local.conf for debugging
if [[ -f "$ZT_HOME/local.conf" ]]; then
    log "local.conf: $(tr -d '\n' < "$ZT_HOME/local.conf")"
fi
```

---

### 5. `Dockerfile` — MODIFY

```dockerfile
# Upgrade Alpine 3.19 → 3.21 for newer zerotier-one package (post-1.14.0 fixes)
FROM alpine:3.21

RUN apk add --no-cache \
    zerotier-one \
    iproute2 \
    iptables \
    ip6tables \
    bash \
    curl \
    jq \
    iputils       # ADD — ping/tracepath for diagnostics inside container
```

---

### 6. `install.sh` — MODIFY

**In the IP forwarding step, also apply host-side kernel tuning:**

```bash
# UDP buffer sizes — host-level (container sysctls handle in-container)
echo "net.core.rmem_max=26214400"          >> /etc/sysctl.conf
echo "net.core.wmem_max=26214400"          >> /etc/sysctl.conf
echo "net.core.netdev_max_backlog=5000"    >> /etc/sysctl.conf
echo "net.ipv4.udp_mem=102400 873800 26214400" >> /etc/sysctl.conf

# NIC offload — improves throughput on J3455 by letting hardware batch packets
ethtool -K eth0 gro on tso on gso on 2>/dev/null || true
ethtool -K eth1 gro on tso on gso on 2>/dev/null || true

sysctl -p
```

---

### 7. `.github/RESEARCH.md` — NEW (commit previously missing)

File exists on disk from earlier research session but was never committed.
Contains: moon architecture, Docker image options, known DSM issues, multipath config,
ZeroNSD notes, action items, and reference links. Commit as-is.

---

## Implementation Order

```
1. config/local.conf        (new)
2. config/rules.v4          (add *raw NOTRACK)
3. docker-compose.yml       (NET_RAW + healthcheck + sysctls + local.conf vol)
4. entrypoint.sh            (conntrack timeout + tc qdisc + local.conf log)
5. Dockerfile               (Alpine 3.21 + iputils)
6. install.sh               (host UDP buffers + ethtool NIC offload)
7. .github/RESEARCH.md      (commit new file)
8. commit + push
```

---

## Verification After Deploy

```sh
# Check NET_RAW is present
docker exec zerotier-moon grep CapEff /proc/1/status

# Check socket buffers in container
docker exec zerotier-moon sysctl net.core.rmem_max

# Confirm local.conf loaded (check log for "local.conf:" line)
docker logs zerotier-moon | grep local.conf

# Check NOTRACK applied
docker exec zerotier-moon iptables -t raw -L -n

# Check healthcheck status
docker inspect zerotier-moon | jq '.[0].State.Health.Status'

# Check fq qdisc on ZT interface
docker exec zerotier-moon tc qdisc show

# Check path quality (latency to peers, relay vs direct)
docker exec zerotier-moon zerotier-cli -j listpeers
# Look for "latencyAvg" and "relayedVia" — direct paths should have low latency, no relay

# Check conntrack timeout
docker exec zerotier-moon sysctl net.netfilter.nf_conntrack_udp_timeout

# Host NIC offload
ethtool -k eth0 | grep -E 'generic-receive-offload|tcp-segmentation|generic-segmentation'
```

---

## Diagnosing a Cutout When It Happens

```sh
# 1. Is the container still up?
docker ps | grep zerotier-moon

# 2. Is ZeroTier alive inside?
docker exec zerotier-moon zerotier-cli status

# 3. Are peers visible and connected?
docker exec zerotier-moon zerotier-cli listpeers
# relayedVia = non-null means traffic is going through ZeroTier's relay (slower, less stable)
# latencyAvg = ms to peer; >200ms suggests routing issue

# 4. Are routes still set?
docker exec zerotier-moon ip rule show
docker exec zerotier-moon ip route show table ISP_1

# 5. Check for dropped packets on ZT interface
docker exec zerotier-moon cat /proc/net/dev | grep zt

# 6. Check conntrack table size
cat /proc/sys/net/netfilter/nf_conntrack_count
cat /proc/sys/net/netfilter/nf_conntrack_max
```
