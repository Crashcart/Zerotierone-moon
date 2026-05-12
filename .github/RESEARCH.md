# Project Research Notes — ZeroTier Moon on DS918+

Compiled from ZeroTier docs, GitHub issues, and community sources.
Informs implementation decisions for this repo.

---

## 1. What a Moon Actually Does

ZeroTier has three tiers of infrastructure:

| Term | What it is |
|------|-----------|
| **Planet** | ZeroTier Inc.'s four globally-distributed public root servers. Always present. |
| **Moon** | A self-hosted supplementary root server. Nodes that "orbit" it use it as an additional relay/relay-discovery point. Does NOT replace planets. |
| **Satellite** | Deprecated concept — ignore. |

A moon **supplements** ZeroTier's public planets — nodes still use public planets but prefer a moon if it responds faster. Primary value:
- Reduces dependency on ZeroTier Inc. infrastructure
- Improves relay reliability for nodes on your local network
- Faster P2P path discovery if the moon is geographically closer

> **Note:** ZeroTier no longer officially recommends self-hosted moons (as of 2024/2025). They still work — they're just de-emphasised.
> Track: https://discuss.zerotier.com/t/private-root-aka-moons-no-longer-suggested-in-zerotier-docs/26114

**Moon vs Network Controller:** A moon is a root/relay server (VL1). A network controller manages membership and policies (VL2). They are completely separate — this repo is a moon only.

---

## 2. Moon Generation Process

```sh
# 1. Generate moon definition from running node's identity
zerotier-idtool initmoon /var/lib/zerotier-one/identity.public > moon.json

# 2. Edit moon.json — set stableEndpoints (must be static IPs — no DDNS)
#    "stableEndpoints": ["192.168.1.253/9993", "172.16.0.253/9993", "<PUBLIC_IP>/9993"]

# 3. Compile
zerotier-idtool genmoon moon.json
# Produces: 0000006xxxxxxx.moon

# 4. Deploy
mkdir -p /var/lib/zerotier-one/moons.d
cp 0000006xxxxxxx.moon /var/lib/zerotier-one/moons.d/

# 5. Orbit own moon
zerotier-cli orbit <MOON_ID> <MOON_ID>
```

**Back up these files — losing identity.secret means losing the moon ID permanently:**
- `/var/lib/zerotier-one/identity.public`
- `/var/lib/zerotier-one/identity.secret`

**Clients orbit:**
```sh
zerotier-cli orbit <MOON_ID> <MOON_ID>
zerotier-cli listpeers | grep MOON   # verify
```

**Maximum 4 root entries per moon.json** — silent failure beyond 4.

---

## 3. Docker Image Options

| Image | Base | Moon-ready | Notes |
|-------|------|-----------|-------|
| `zerotier/zerotier` | Debian | Manual | Official generic. Multi-arch. |
| `zerotier/zerotier-synology` | ? | Manual | Official Synology-specific. **amd64 only.** |
| `zyclonite/zerotier` | Alpine | Manual | Lightweight, popular. Has `-router` variant for LAN bridging. |
| `seedgou/zerotier-moon` | ? | **Yes** | Purpose-built moon. Single-command setup. |
| `rwv/docker-zerotier-moon` | ? | **Yes** | One-step moon. Multi-arch. Good compose examples. |

This repo builds a custom Alpine image for full control. Evaluate `seedgou` / `rwv` as simpler alternatives.

---

## 4. Port Forwarding — Required for External Clients

- ZeroTier uses **UDP 9993 only**
- Router must forward **UDP 9993 → NAS IP:9993** for external clients
- `stableEndpoints` must include the **public IP** (not DDNS — not supported)
- Avoid symmetric NAT; use full-cone or port-restricted-cone
- No more than one NAT layer between moon and internet

DSM firewall: Add Allow rule for UDP 9993 inbound.

---

## 5. Known Issues on Synology DSM 7

### DNS/Directory Server Conflict (Critical)

ZeroTier on DSM 7.2.2 **breaks DNS resolution and Directory Server logins**.
- Source: https://discuss.zerotier.com/t/synology-nas-with-zt-breaks-directory-server-services/27671
- Mitigation: macvlan may avoid the conflict vs `--net=host`

### TCP Traffic Blocked in Docker

Ping works but TCP/HTTP doesn't pass through ZeroTier interface.
- GitHub: https://github.com/zerotier/ZeroTierOne/issues/1830
- Fix: **Add `NET_RAW` capability** alongside `NET_ADMIN`. Host network mode preferred.

### Routing Table Lost on Reboot

All `ip route` / `ip rule` entries wiped when DSM reboots.
- Source: https://discuss.zerotier.com/t/synology-docker-routing-table-entries-do-not-survive-reboot/4079
- Fix: `setuproutes.sh` in `/var/lib/zerotier-one/` re-runs on every container start (handled in `entrypoint.sh`)

### Version 1.14.0 Bug — Networks Not Syncing

`zerotier-cli listnetworks` returns nothing after join on some Synology setups.
- GitHub: https://github.com/zerotier/ZeroTierOne/issues/2324
- Fix: Pin to a known-good version in Dockerfile

### Container Manager GUI Drops Advanced Config

Re-editing a macvlan container via GUI silently resets network configuration.
- Fix: Manage exclusively via `docker compose` or CLI.

---

## 6. Required Docker Capabilities

```yaml
cap_add:
  - NET_ADMIN    # network configuration
  - NET_RAW      # raw sockets, iptables raw table — REQUIRED to prevent TCP drops
  - SYS_ADMIN    # TUN device management
devices:
  - /dev/net/tun
```

`NET_RAW` is the most commonly missed capability. Several Synology TCP cutout issues trace back to it.

---

## 7. Dual-NIC / Multipath

ZeroTier has built-in multipath bonding via `local.conf` (separate from OS-level `setuproutes.sh`):

| Policy | Behaviour |
|--------|----------|
| `active-backup` | One primary NIC, failover spare |
| `balance-xor` | Traffic striped across links |
| `balance-aware` | Flows hashed by src/dst port + protocol |

Example `local.conf` active-backup for DS918+:
```json
{
  "settings": {
    "defaultBondingPolicy": "active-backup",
    "active-backup": {
      "linkSelectMethod": "always",
      "links": {
        "eth0": { "failoverTo": "eth1", "mode": "primary" },
        "eth1": { "mode": "spare" }
      }
    }
  }
}
```

Monitor: `zerotier-cli bond list`

---

## 8. Bridging ZeroTier to Physical LAN

To make physical LAN devices reachable from ZeroTier clients:
1. `net.ipv4.ip_forward=1` — done in `install.sh`
2. ZeroTier Central → Managed Routes: add `192.168.1.0/24` via NAS ZeroTier IP
3. Masquerade already in `config/rules.v4`

Use `/23` instead of `/24` so physical machines prefer direct connection over ZT path.

---

## 9. ZeroNSD — DNS for ZeroTier Networks

Provides hostname resolution inside ZeroTier (`mynas.home.arpa`). Pulls node names from ZeroTier Central API.
- **One ZeroNSD per network only**
- Run as a second compose service on the same NAS

```sh
docker run --net host -d \
  -v /var/lib/zerotier-one/authtoken.secret:/authtoken.secret \
  -v /path/to/central-token:/token.txt \
  zerotier/zeronsd start -s /authtoken.secret -t /token.txt <NETWORK_ID>
```

GitHub: https://github.com/zerotier/zeronsd

---

## 10. Security Notes

- All ZeroTier traffic E2E encrypted (Salsa20/Poly1305, Curve25519)
- Moon cannot inspect traffic — relay discovery only
- **Back up `identity.secret`** — losing it loses the moon ID permanently
- Moon only needs UDP 9993 exposed
- DSM firewall: allow UDP 9993 inbound; block everything else

---

## 11. Open Action Items

- [x] Add `NET_RAW` cap to `docker-compose.yml` and `install.sh`
- [ ] Pin ZeroTier version in Dockerfile — avoid 1.14.0 bug
- [ ] Add `local.conf` to `config/` with port pinning + TCP fallback
- [ ] Add conntrack bypass (NOTRACK) for UDP 9993 in `config/rules.v4`
- [ ] Add UDP socket buffer tuning to `install.sh` and compose `sysctls`
- [ ] Add Docker healthcheck using `zerotier-cli status`
- [ ] Add ZeroNSD as second compose service
- [ ] Add managed routes instructions to README
- [ ] Port forward UDP 9993 on router if serving external clients
- [ ] Evaluate `seedgou/zerotier-moon` or `rwv/docker-zerotier-moon` as simpler alternatives

---

## 12. Reference Links

| Resource | URL |
|----------|-----|
| ZeroTier Moons | https://docs.zerotier.com/roots/ |
| ZeroTier Docker | https://docs.zerotier.com/docker/ |
| ZeroTier Synology | https://docs.zerotier.com/synology/ |
| ZeroTier Multipath | https://docs.zerotier.com/multipath/ |
| ZeroTier Bridging | https://docs.zerotier.com/bridging/ |
| ZeroTier Managed Routes | https://docs.zerotier.com/route-between-phys-and-virt/ |
| ZeroTier Router Tips | https://docs.zerotier.com/routertips/ |
| ZeroNSD | https://github.com/zerotier/zeronsd |
| ZeroTierOne GitHub | https://github.com/zerotier/ZeroTierOne |
| zyclonite/zerotier | https://github.com/zyclonite/zerotier-docker |
| rwv/docker-zerotier-moon | https://github.com/rwv/docker-zerotier-moon |
| seedgou/zerotier-moon | https://hub.docker.com/r/seedgou/zerotier-moon |
| Routing persistence thread | https://discuss.zerotier.com/t/synology-docker-routing-table-entries-do-not-survive-reboot/4079 |
| TCP issue #1830 | https://github.com/zerotier/ZeroTierOne/issues/1830 |
| DNS conflict thread | https://discuss.zerotier.com/t/synology-nas-with-zt-breaks-directory-server-services/27671 |
| v1.14.0 bug #2324 | https://github.com/zerotier/ZeroTierOne/issues/2324 |
| Moons de-emphasised | https://discuss.zerotier.com/t/private-root-aka-moons-no-longer-suggested-in-zerotier-docs/26114 |
