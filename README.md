# ZeroTier Moon — Synology DS918+

Self-hosted ZeroTier moon node running on a Synology DS918+ via Docker (Container Manager).
Configured for dual-NIC operation so the moon is reachable from both physical networks.

> A **moon** is a self-hosted ZeroTier root server. Clients that orbit it no longer depend
> solely on ZeroTier's public infrastructure — connections are faster and work even if
> ZeroTier's hosted roots are unreachable.

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

## Step 5 — Deploy the Container (Container Manager UI)

Container Manager → Container → Create → select **Create from URL** (or import the compose file below).

### Compose file

```yaml
services:
  zerotier:
    image: ddeitterick/zerotier-gateway
    container_name: zerotier-moon
    restart: always
    devices:
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    networks:
      macvlan-lan1:
        ipv4_address: 192.168.1.253
    ports:
      - "9993:9993/udp"
    volumes:
      - /volume1/docker/zerotier/zerotier-one:/var/lib/zerotier-one
      - /volume1/docker/zerotier/iptables:/etc/iptables
      - /volume1/docker/zerotier/iproute2/rt_tables:/etc/iproute2/rt_tables
    environment:
      - NETWORK_IDS=<YOUR_ZT_NETWORK_ID>
      - DOCKER_HOST=192.168.1.253
      - MULTIPATH=Enabled

networks:
  macvlan-lan1:
    external: true
  macvlan-lan2:
    external: true
```

After the container is created, **attach the second network**:

Container Manager → Container → zerotier-moon → Edit → Network → Add `macvlan-lan2` → assign a static IP (e.g. `172.16.x.253`).

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

If the NAS has a public IP or DDNS hostname, add that too:

```json
"stableEndpoints": [
  "192.168.1.253/9993",
  "172.16.x.253/9993",
  "<PUBLIC_IP_OR_DDNS>/9993"
]
```

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

```
*nat
-I POSTROUTING -o zt+ -j MASQUERADE
-I POSTROUTING -o eth0 -j MASQUERADE
-I POSTROUTING -o eth1 -j MASQUERADE
COMMIT
```

---

## Reboot Persistence

Routes inside Docker containers are wiped on reboot. The `setuproutes.sh` approach
re-applies them every time the container starts.

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

## References

- [Synology | ZeroTier Docs](https://docs.zerotier.com/synology/)
- [ZeroTier Moons](https://docs.zerotier.com/moons/)
- [ddeitterick/zerotier-gateway](https://github.com/ddeitterick/zerotier-gateway) — dual-NIC gateway image
- [Routing persistence thread](https://discuss.zerotier.com/t/synology-docker-routing-table-entries-do-not-survive-reboot/4079)
