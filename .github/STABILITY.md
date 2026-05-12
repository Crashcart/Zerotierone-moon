# Stability & Throughput Reference

> **Status: ✅ All changes implemented** (commit `aa86507`, 2026-05-12)

This document covers the diagnosed causes of cutouts and throughput bottlenecks on the
DS918+ ZeroTier moon, and the changes made to address them. Use it to understand WHY
each tuning parameter exists, and for diagnosing future issues.

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

---

## Sr Network Engineer Review Findings (2026-05-12)

A full network engineering review identified the following issues, all fixed in the same session:

### Fixed

| # | Finding | Fix |
|---|---------|-----|
| 1 | `setuproutes.sh` had literal `172.16.x.*` placeholder values — `ip route add` failed silently, eth1 policy routing was dead | `install.sh` generates the file with real values; `config/setuproutes.sh` updated as reference template |
| 2 | `ip rule add` entries were not idempotent — duplicate rules accumulated on every container restart | Added `ip rule del table ISP_1/ISP_2` flush before re-adding |
| 3 | No `ip rule` entries for the container's own source IPs — ZeroTier daemon outbound traffic (keepalives, planet pings) used main table and could egress the wrong NIC | Added `ip rule add from $IP1 table ISP_1 priority 98` and `from $IP2 table ISP_2 priority 99` |
| 4 | No main-table default route fallback — ZeroTier traffic to public planet servers (not matching any /24 rule) was black-holed | Added `ip route replace default via $P1 metric 200` to main table |
| 5 | `conntrack UDP timeout` sysctl writes silently failed — `net.netfilter.*` is in the HOST network namespace, inaccessible from a namespaced container | Moved to `install.sh` host sysctl.conf; `entrypoint.sh` now logs clearly if write fails |
| 6 | No `*filter` FORWARD rules in `rules.v4` — Docker macvlan does not inject ACCEPT rules; ZeroTier relay/gateway traffic (zt+ ↔ eth0/eth1) may be dropped by default FORWARD DROP | Added explicit FORWARD ACCEPT rules for zt+↔eth0 and zt+↔eth1 in both directions |
| 7 | MASQUERADE rules too broad (`-I POSTROUTING -o eth0 -j MASQUERADE`) — all traffic on eth0/eth1 was NAT'd, not just ZeroTier-forwarded traffic | Scoped with `-i zt+` in POSTROUTING to match only forwarded ZT flows |
| 8 | `ports: 9993:9993/udp` in `docker-compose.yml` is dead configuration under macvlan | Replaced with a comment; router port-forward documented |
| 9 | `fq` qdisc applied before `zerotier-cli join` — the `zt*` interface does not exist yet on first start | Moved qdisc setup to after the join block; logs a note if no interface found |
| 10 | No gratuitous ARP on container start — ARP cache stale for up to 300s after restart | Added `arping -A -c 3` for each physical interface in `entrypoint.sh` |
| 11 | `"zt"` missing from `interfacePrefixBlacklist` in `local.conf` — ZeroTier could probe its own interfaces as candidate paths | Added `"zt"` and `"macvlan"` to the blacklist |
| 12 | 25 MB socket buffers oversized for J3455 + ZeroTier (~200-600 Mbps effective throughput) — caused unnecessary kernel cache pressure | Reduced to 8 MB (≈ 2× BDP at 300 Mbps / 100ms RTT) |

### Known Limitations (architectural — no fix without major redesign)

| # | Limitation | Notes |
|---|-----------|-------|
| A | **macvlan host isolation** — the NAS host cannot communicate with the ZeroTier container via its macvlan IP | `docker exec` works via Unix socket; management via Container Manager UI is unaffected. DSM services cannot reach the container by IP directly. |
| B | **No eth1 failover** — if eth1 goes down, ISP_2 table still routes via dead gateway; ZeroTier path reconverges in ~125s | For resilience, add a link-monitor script that flushes the ISP_2 table when eth1 loses carrier |
| C | **`ports:` under macvlan is a no-op** — upstream router must be manually configured to forward UDP 9993 to the container's macvlan IP | Document in README; `portMappingEnabled: true` in `local.conf` handles UPnP if the router supports it |
| D | **SYS_ADMIN capability is broad** — only required if the sysctl writes in entrypoint.sh need host-ns access; could be dropped now that conntrack tuning moved to host | Consider dropping SYS_ADMIN in a future hardening pass |
