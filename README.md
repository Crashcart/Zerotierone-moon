# ZeroTier Moon — Synology DS918+

Self-hosted ZeroTier moon node running on a Synology DS918+ via Docker (Container Manager).
Configured for dual-NIC operation so the moon is reachable from both physical networks.

> A **moon** is a self-hosted ZeroTier root server. Clients that orbit it no longer depend
> solely on ZeroTier's public infrastructure — connections are faster and work even if
> ZeroTier's hosted roots are unreachable.

---

## Quick Start

Everything is driven by a single CLI: **`zmoon`**.

```sh
# 1. SSH into the NAS as root
ssh admin@<NAS_IP> && sudo -i
cd /path/to/this/repo

# 2. Configure (copy the example and edit your subnets/IPs)
cp .env.example .env && vi .env

# 3. Install — builds the image, creates macvlan nets, generates the moon
./zmoon install

# 4. Verify everything is healthy
./zmoon doctor

# 5. Get the Moon ID + the command to run on every client
./zmoon moon-id
```

| Command | What it does |
|---------|--------------|
| `zmoon install` | First-time setup (image, networks, moon, container) |
| `zmoon update [--branch X] [--no-build]` | Rebuild + restart without touching the moon identity |
| `zmoon status` | One-screen health summary (container, ZT, moon, peers) |
| `zmoon doctor` | Full automated diagnostics — PASS/WARN/FAIL, non-zero exit on failure (cron-friendly) |
| `zmoon peers` | Parsed peer table: address, role, latency, direct vs relayed |
| `zmoon moon-id` | Print the Moon ID and the client `orbit` command |
| `zmoon backup` | Back up the moon identity (auto-prunes to last 5) |
| `zmoon restore <dir>` | Restore the moon identity from a backup |
| `zmoon logs [-f]` | Show / follow container logs |
| `zmoon autoupdate` | Auto-update check (run from cron — respects `AUTO_UPDATE` in `.env`) |
| `zmoon version` | zmoon + running ZeroTier version |

`zmoon install` / `zmoon update` simply delegate to `install.sh` / `update.sh`, so the
detailed manual walkthrough below is still accurate if you prefer the Container Manager UI.

---

## Hardware

| Item | Detail |
|------|--------|
| Device | Synology DS918+ |
| NICs | 2x RJ-45 1GbE — `eth0` (LAN 1) and `eth1` (LAN 2) |
| OS | Synology DSM 7.x |
| Container runtime | Container Manager (DSM package — replaces old Docker package) |

> **Bonding note**: If Link Aggregation is enabled in DSM (Control Panel → Network → Network Interface),
> both ports appear as `ovs_bond0` instead of `eth0`/`eth1`. For dual-network ZeroTier,
> bonding should be **disabled** so each NIC stays on its own subnet.

---

## Prerequisites

- Container Manager installed via DSM Package Center
- A fixed/static IP (or DDNS) for each NIC — the moon needs stable endpoints
- Outbound UDP 9993 open on your firewall/router
- SSH enabled **temporarily** for initial setup (see below)

---

## Step 1 — Enable SSH (temporary)

DSM 7 locks down shell access by default. Enable it just long enough to do the one-time host configuration.

**DSM UI**: Control Panel → Terminal & SNMP → Terminal tab → check **Enable SSH service** → Apply

Connect:
```sh
ssh admin@<NAS_IP>
sudo -i
```

You can disable SSH again after Step 3.

---

## Step 2 — Enable IP Forwarding (one-time, requires SSH)

```sh
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
```

Verify:
```sh
sysctl net.ipv4.ip_forward
# Should print: net.ipv4.ip_forward = 1
```

> DSM may reset `/etc/sysctl.conf` on major updates. Re-run this after DSM upgrades.

---

## Step 3 — Create Data Directories (requires SSH)

```sh
mkdir -p /volume1/docker/zerotier/zerotier-one/moons.d
mkdir -p /volume1/docker/zerotier/iproute2
mkdir -p /volume1/docker/zerotier/iptables
```

Copy config files from this repo into place:
```sh
cp config/rt_tables    /volume1/docker/zerotier/iproute2/rt_tables
cp config/rules.v4     /volume1/docker/zerotier/iptables/rules.v4
cp config/setuproutes.sh /volume1/docker/zerotier/zerotier-one/setuproutes.sh
chmod +x /volume1/docker/zerotier/zerotier-one/setuproutes.sh
```

You can now **disable SSH** again if you prefer.

---

## Step 4 — Create Docker Networks (Container Manager UI)

> All of the following can be done without SSH via **Container Manager → Network**.

### macvlan for LAN 1 (eth0)

Container Manager → Network → Add → choose **macvlan**:

| Field | Value |
|-------|-------|
| Network name | `macvlan-lan1` |
| Parent interface | `eth0` |
| Subnet | `192.168.1.0/24` *(your LAN 1 subnet)* |
| Gateway | `192.168.1.1` |
| IP range | `192.168.1.252/30` *(reserve 2 IPs for the container)* |

### macvlan for LAN 2 (eth1)

Repeat for LAN 2:

| Field | Value |
|-------|-------|
| Network name | `macvlan-lan2` |
| Parent interface | `eth1` |
| Subnet | `172.16.x.0/24` *(your LAN 2 subnet)* |
| Gateway | `172.16.x.1` |
| IP range | `172.16.x.252/30` |

> **macvlan caveat**: containers on a macvlan cannot reach the NAS host directly, and vice versa.
> This is fine for a moon node — ZeroTier clients connect to the container's own IP.

---

## Step 5 — Deploy the Container

> **Recommended**: skip steps 2–5 entirely and use `zmoon install` — it handles IP forwarding,
> directories, macvlan networks, image build, and container start in one command.

If you prefer manual setup via Container Manager UI:

1. Build the image on the NAS via SSH: `docker build -t zerotier-moon /path/to/this/repo`
2. Container Manager → Container → Create → import the compose file below

### Compose file

`install.sh` generates `docker-compose.yml` with your values filled in. The template it uses:

```yaml
services:
  zerotier:
    image: zerotier-moon        # built locally by install.sh from Dockerfile
    container_name: zerotier-moon
    restart: always
    devices:
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
      - NET_RAW                 # required for iptables raw table (NOTRACK)
      - SYS_ADMIN
    sysctls:
      net.core.rmem_max: 8388608
      net.core.wmem_max: 8388608
      net.core.netdev_max_backlog: 5000
      net.ipv4.udp_rmem_min: 8192
      net.ipv4.udp_wmem_min: 8192
    healthcheck:
      test: ["CMD", "zerotier-cli", "status"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    networks:
      macvlan-lan1:
        ipv4_address: 192.168.1.253    # your LAN 1 container IP
      macvlan-lan2:
        ipv4_address: 172.16.0.253     # your LAN 2 container IP
    volumes:
      - /volume1/docker/zerotier/zerotier-one:/var/lib/zerotier-one
      - /volume1/docker/zerotier/iptables:/etc/iptables
      - /volume1/docker/zerotier/iproute2/rt_tables:/etc/iproute2/rt_tables
      - /volume1/docker/zerotier/local.conf:/var/lib/zerotier-one/local.conf:ro
    environment:
      - NETWORK_IDS=<YOUR_ZT_NETWORK_ID>
      - GENERATE_MOON=true
      - MOON_ENDPOINTS=192.168.1.253/9993,172.16.0.253/9993

networks:
  macvlan-lan1:
    external: true
  macvlan-lan2:
    external: true
```

> **NOTE:** `ports:` has no effect under macvlan networking. Forward **UDP 9993** on your
> router directly to the container's macvlan IP (e.g. `192.168.1.253`).

---

## Step 6 — Join a ZeroTier Network

Once the container is running, join your network via the Container Manager terminal
(Container → zerotier-moon → Terminal → bash), or via SSH:

```sh
docker exec zerotier-moon zerotier-cli join <NETWORK_ID>
```

Authorize the node at [my.zerotier.com](https://my.zerotier.com) (Members tab).

---

## Step 7 — Generate the Moon

This turns the DS918+ into a self-hosted root server.

Open a terminal in the container:
```sh
docker exec -it zerotier-moon bash
```

```sh
# Generate moon definition from the node's identity
zerotier-idtool initmoon /var/lib/zerotier-one/identity.public > /var/lib/zerotier-one/moon.json
```

Edit `/var/lib/zerotier-one/moon.json` — find the `"stableEndpoints"` array and add both NIC IPs:

```json
"stableEndpoints": [
  "192.168.1.253/9993",
  "172.16.x.253/9993"
]
```

If the NAS has a static public IP, add it too:

```json
"stableEndpoints": [
  "192.168.1.253/9993",
  "172.16.x.253/9993",
  "<PUBLIC_IP>/9993"
]
```

> **Important:** `stableEndpoints` requires bare IP addresses — ZeroTier does **not** resolve
> hostnames or DDNS names. Use the actual IPv4/IPv6 address only.

Compile and deploy the moon:

```sh
cd /var/lib/zerotier-one
zerotier-idtool genmoon moon.json
# Produces a file like: 0000006xxxxxxx.moon

mkdir -p moons.d
cp 0000006xxxxxxx.moon moons.d/

# Reload ZeroTier
zerotier-cli orbit <MOON_ID> <MOON_ID>
```

The moon ID is the 10-digit hex prefix of the `.moon` filename.

---

## Step 8 — Orbit the Moon on Clients

On every ZeroTier client that should use this moon:

```sh
zerotier-cli orbit <MOON_ID> <MOON_ID>
```

Verify it's listed:
```sh
zerotier-cli listpeers | grep MOON
```

---

## Routing & NAT (Dual-NIC)

The files in `config/` are mapped into the container and handle return-path routing
for both NICs. Update the placeholder values to match your network before deploying.

### `config/setuproutes.sh`

Runs automatically on container start. Sets up policy routing so traffic from each
subnet exits via the correct NIC.

```sh
#!/bin/sh
# Edit these values for your network
IF1="eth0"   IF2="eth1"
IP1="192.168.1.253"   IP2="172.16.x.253"
P1="192.168.1.1"      P2="172.16.x.1"
P1_NET="192.168.1.0/24"
P2_NET="172.16.x.0/24"
TBL1="ISP_1"          TBL2="ISP_2"

ip route add $P1_NET dev $IF1 src $IP1 table $TBL1
ip route add default via $P1 table $TBL1
ip route add $P2_NET dev $IF2 src $IP2 table $TBL2
ip route add default via $P2 table $TBL2
ip rule add from $P1_NET table $TBL1
ip rule add from $P2_NET table $TBL2
```

### `config/rt_tables`

```
255    local
254    main
253    default
0      unspec
101    ISP_1
102    ISP_2
```

### `config/rules.v4`

Reference template — `install.sh` writes the production copy with your interface names.

```
*raw
-A PREROUTING -p udp --dport 9993 -j NOTRACK
-A OUTPUT -p udp --sport 9993 -j NOTRACK
COMMIT

*mangle
-A FORWARD -i zt+ -j MARK --set-mark 0x2a
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
COMMIT

*filter
-A FORWARD -i zt+ -o eth0 -j ACCEPT
-A FORWARD -i zt+ -o eth1 -j ACCEPT
-A FORWARD -i eth0 -o zt+ -j ACCEPT
-A FORWARD -i eth1 -o zt+ -j ACCEPT
-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
COMMIT

*nat
-A POSTROUTING -m mark --mark 0x2a -j MASQUERADE
-A POSTROUTING -o zt+ -j MASQUERADE
COMMIT
```

> **Why the `0x2a` mark?** `iptables` forbids `-i` (input interface) in
> `POSTROUTING`, and `iptables-restore` is atomic — a single bad line drops the
> *entire* ruleset. ZeroTier-forwarded packets are marked in `mangle`/FORWARD
> and the mark is matched in `nat`/POSTROUTING to scope MASQUERADE correctly.

---

## Reboot Persistence

Two layers survive a reboot independently:

- **Container internals** (routes, iptables, fq qdisc, gratuitous ARP) — the
  container is `restart: always`, and `setuproutes.sh` + `entrypoint.sh`
  re-apply everything each time it starts.
- **Host tuning** (8 MB UDP socket buffers, `netdev_max_backlog`, conntrack UDP
  timeout 300s, GRO/TSO/GSO NIC offload) — DSM does **not** reliably re-read
  `/etc/sysctl.conf` on boot and offload always resets, so this must be
  re-applied. `zmoon boot` does it (idempotent, logs to `$DATA_DIR/boot.log`).

### Wire `zmoon boot` to a Boot-up task (do this once)

Without it, the moon comes back after a reboot **slower** (small buffers, no
offload) and **less stable** (default 30s conntrack timeout < ZeroTier's ~25s
keepalive → periodic UDP cutouts).

> **DSM is not standard Linux — this matters here.** Task Scheduler and cron run
> scripts with a **minimal PATH** (no `/usr/local/bin`, no `/sbin`, no Container
> Manager dir) and as a bare user. So:
> - Always use the **absolute path** to `zmoon` in the task — a bare `zmoon boot`
>   may not be found. `zmoon` itself repairs its PATH internally, but the
>   scheduler still has to locate the script.
> - The task **must run as `root`** — `sysctl`, `ethtool`, and `docker` all need it.

#### Option A — GUI Boot-up task (event-driven, recommended)

**Control Panel → Task Scheduler → Create → Triggered Task → User-defined script**

| Field | Value |
|-------|-------|
| **Task** | `zmoon boot tuning` |
| **User** | `root` |
| **Event** | `Boot-up` |
| **Run command** | `/usr/local/bin/zmoon boot` |

Save. To test it without rebooting: select the task → **Run**. Then check the
log: `cat /volume1/docker/zerotier/boot.log` — you should see a fresh
`host tuning re-applied …` line. (Adjust the path if your `DATA_DIR` differs.)

`zmoon boot` re-applies the host tuning and ensures the container is started —
the values come from `lib/tuning.sh`, the same source the installer uses, so
they never drift.

#### Option B — cron, from the command line (no GUI)

```sh
sudo /usr/local/bin/zmoon install-cron        # every 15 min (default)
sudo /usr/local/bin/zmoon install-cron "0 * * * *"   # or a custom 5-field schedule
sudo /usr/local/bin/zmoon uninstall-cron      # remove it
```

This appends a **tab-separated** entry (the format DSM's crond requires — spaces
between columns make DSM silently drop the line) to `/etc/crontab` and reloads
crond via `synosystemctl`/`synoservice`. A **periodic** schedule is used rather
than `@reboot`, which DSM's stripped crond does not honor; the periodic run is
idempotent and also self-heals tuning lost to a DSM package update mid-cycle.

> Note: a DSM **major-version upgrade** can reset `/etc/crontab`. After a big DSM
> update, re-run `zmoon install-cron` (or just re-run `install.sh`). The GUI
> Boot-up task in Option A survives DSM updates more reliably — if in doubt, set
> up both; `zmoon boot` is idempotent, so running it twice is harmless.

### Connecting a client — populated commands

`zmoon connect` prints the exact, ready-to-paste client commands for **this**
moon, with the 10-char Moon ID and network ID already filled in (install → join
→ orbit → verify, plus the Windows `.moon`-file path). The browser console's
**Connect** tab shows the same, auto-filled from live status.

### Fresh install won't crash-loop

If the container starts before it can work (data dir not yet mounted, `/dev/net/tun`
missing, identity not generated), it does **not** exit under `restart: always` —
that would spin forever. Instead it **holds alive and idle**, the healthcheck goes
unhealthy, and `docker logs zerotier-moon` prints the exact reason plus the fix
(`zmoon update --no-build`). A running-but-unhealthy container is not restarted by
Docker, so there is no reboot loop to burn CPU or flood logs.

If you hit issues after a reboot:

1. Check the container started: Container Manager → Container → Status = Running
2. Force re-apply routes: Container Manager → Container → zerotier-moon → Restart
3. Verify routes inside the container:
   ```sh
   docker exec zerotier-moon ip rule show
   docker exec zerotier-moon ip route show table ISP_1
   ```

For `net.ipv4.ip_forward`, re-check after DSM updates:
```sh
sysctl net.ipv4.ip_forward
```

---

## Firewall — DSM Security Advisor

DSM's built-in firewall (Control Panel → Security → Firewall) may block port 9993/UDP.

Add a rule: **Allow** | Source: Any | Port: 9993 | Protocol: UDP

---

## Updating

`zmoon update` safely rebuilds and restarts without touching the moon identity:

```sh
# Rebuild image and restart (identity is backed up automatically)
zmoon update

# Skip rebuild, just restart container (e.g. after a reboot)
zmoon update --no-build

# Upgrade to a different branch before rebuilding
zmoon update --branch main   # stable
zmoon update --branch beta
zmoon update --branch dev    # latest

# Check current status only
zmoon update --status
```

`zmoon update` always verifies `identity.secret` exists before doing anything, backs up the
moon identity to a timestamped directory, regenerates `docker-compose.yml` from the current
template and your `.env` values, and recreates macvlan networks if they were lost on reboot.

### Old install — bring current (one-time)

If your install predates the `zmoon` CLI:

```sh
sudo ln -sf /volume1/docker/zerotierone-moon/zmoon /usr/local/bin/zmoon
zmoon update --branch dev
```

### Daily auto-update

Enable in `.env`:

```sh
AUTO_UPDATE=true
AUTO_UPDATE_BRANCH=dev   # or: main, beta
```

Add to **DSM Task Scheduler** (Control Panel → Task Scheduler → Create → Scheduled Task → User-defined script):

- **User**: `root` | **Schedule**: Daily, 03:00
- **Command**: `zmoon autoupdate`

`zmoon autoupdate` checks the remote for new commits, no-ops if already up-to-date or if
`AUTO_UPDATE=false`, and logs to `$DATA_DIR/autoupdate.log` (1 MB rotation).

```sh
# Check the log
tail -f /volume1/docker/zerotier/autoupdate.log
```

---

## Stability Tuning

The following are applied automatically by `install.sh` and `entrypoint.sh`:

| Improvement | Where | Effect |
|-------------|-------|--------|
| `NET_RAW` capability | `docker-compose.yml` | Enables iptables raw table (required for NOTRACK) |
| NOTRACK for UDP 9993 | `config/rules.v4` | Removes ZeroTier from conntrack — prevents 30s timeout cutouts |
| `*filter` FORWARD rules | `config/rules.v4` | Allows ZT↔LAN forwarding (macvlan has no automatic ACCEPT rules) |
| Mark-scoped MASQUERADE | `config/rules.v4` | `mangle` marks ZT-forwarded packets; `nat` matches the mark — only NATs ZeroTier-forwarded traffic (POSTROUTING can't match `-i`) |
| conntrack UDP timeout → 300s | host `sysctl.conf` via `install.sh` | Belt-and-suspenders; must be set on the DSM host (not inside container) |
| 8 MB UDP socket buffers | compose `sysctls` + host `sysctl.conf` | ~2× BDP for ZT on J3455; 25 MB was oversized and caused cache pressure |
| Docker healthcheck | `docker-compose.yml` | Auto-restarts container if daemon hangs |
| `config/local.conf` | mounted into container | Pins port 9993, enables TCP fallback, blacklists Docker/ZT/macvlan interfaces |
| `fq` qdisc on ZT interface | `entrypoint.sh` (after network join) | Reduces bufferbloat under sustained load |
| Gratuitous ARP on start | `entrypoint.sh` | Clears stale ARP cache on LAN switches immediately after restart |
| Container-IP routing rules | `setuproutes.sh` | ZeroTier daemon's own keepalives/handshakes egress the correct NIC |
| `ip rule` flush on restart | `setuproutes.sh` | Prevents duplicate policy rules accumulating across container restarts |
| Main-table fallback route | `setuproutes.sh` | Allows ZeroTier to reach public planet/root servers outside local subnets |
| GRO/TSO/GSO NIC offload | `install.sh` ethtool | Lets J3455 hardware batch packets |
| Alpine 3.21 | `Dockerfile` | Newer zerotier-one package (past 1.14.0 Synology bug) |
| TCP MSS clamping | `config/rules.v4` + `config/rules.v6` | `TCPMSS --clamp-mss-to-pmtu` on SYN/SYN-ACK in `*mangle`; prevents silent TCP black holes when ZT overlay MTU (~1400B effective) < physical NIC MTU (1500B) |
| IPv6 FORWARD + MSS | `config/rules.v6` | ip6tables mirror of the IPv4 ruleset — ZT↔LAN forwarding, ICMPv6 (required for NDP/PMTU/RAs), MSS clamping; no NAT (IPv6 uses global addresses) |
| IPv6 forwarding on host | `install.sh` sysctl | `net.ipv6.conf.all.forwarding=1` — without this the kernel silently drops forwarded IPv6 packets regardless of ip6tables rules |

> **macvlan + port forwarding:** The `ports:` directive in `docker-compose.yml` has **no effect** under macvlan networking — Docker does not create DNAT rules for macvlan containers. Configure your router to forward **UDP 9993** directly to the container's macvlan IP (e.g. `192.168.1.253`). `portMappingEnabled: true` in `local.conf` will attempt UPnP/NAT-PMP automatically if your router supports it.

`zmoon doctor` automates the full diagnostic checklist (NET_RAW, NOTRACK, socket
buffers, fq qdisc, policy-routing rule count, conntrack timeout, relayed peers,
host IPv6 forwarding, container ip6tables rules) across 13 PASS/WARN/FAIL checks
and exits non-zero if anything fails — wire it into DSM Task Scheduler for
unattended monitoring. See `.github/STABILITY.md` for the underlying rationale.

---

## Testing

A dependency-free test suite validates shell syntax, ShellCheck cleanliness,
config-file correctness (including a regression guard for the illegal `-i` in
`POSTROUTING` that silently broke the whole iptables ruleset), and the `zmoon`
CLI's offline behaviour:

```sh
bash tests/run.sh
```

It runs in CI on every push/PR (`.github/workflows/test.yml`). ShellCheck runs
against every shell script via `.github/workflows/lint.yml`.

---

## References

- [Synology | ZeroTier Docs](https://docs.zerotier.com/synology/)
- [ZeroTier Moons](https://docs.zerotier.com/moons/)
- [ddeitterick/zerotier-gateway](https://github.com/ddeitterick/zerotier-gateway) — dual-NIC gateway image
- [Routing persistence thread](https://discuss.zerotier.com/t/synology-docker-routing-table-entries-do-not-survive-reboot/4079)
