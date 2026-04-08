# TODO

## Review Items

- [ ] **Implement ZeroTier on DS918+ (dual NIC)** — https://docs.zerotier.com/synology/

---

## DS918+ Setup Notes

### Hardware (DS918+ confirmed specs)

- **2x RJ-45 1GbE LAN ports** — `eth0` (LAN 1) and `eth1` (LAN 2)
- Each NIC can be on a different subnet/network
- DSM supports **Link Aggregation** — if bonding is active, both ports become `ovs_bond0`
  - **For dual-network ZeroTier**: keep bonding OFF so eth0/eth1 remain independent
  - **If bonding is ON**: use `ovs_bond0` as the macvlan parent (single network only)
- Both NICs must be reachable via ZeroTier independently

### Prerequisites (on the NAS host)

```sh
# Enable IP forwarding — persistent across reboots
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
```

---

### Option A — Simple (`--net=host`)

Uses `--net=host` so the container shares the host network stack.
Works if both NICs route to the same ZeroTier-connected network, or if upstream
router handles return-path routing.

```sh
docker run -d \
  --name zerotier-one \
  --restart=always \
  --device=/dev/net/tun \
  --net=host \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_ADMIN \
  -v /volume1/docker/zerotier-one:/var/lib/zerotier-one \
  zerotier/zerotier-synology:latest
```

After start:

```sh
docker exec zerotier-one zerotier-cli join <NETWORK_ID>
# Authorize the node at https://my.zerotier.com
```

> **Limitation**: with `--net=host`, Linux picks a single default gateway — traffic
> from the second NIC may return via the wrong interface. Use Option B to fix this.

---

### Option B — Dual-NIC Gateway (recommended for DS918+)

Uses [`ddeitterick/zerotier-gateway`](https://github.com/ddeitterick/zerotier-gateway)
with macvlan + policy routing so traffic sourced from each subnet always returns
via the correct NIC. Enables `MULTIPATH` for both interfaces.

#### 1. Create macvlan network (anchored to eth0)

```sh
docker network create \
  --driver macvlan \
  --gateway 192.168.1.1 \
  --subnet 192.168.1.0/24 \
  -o parent=eth0 \
  macvlan1
```

> If Link Aggregation is enabled in DSM Control Panel, replace `eth0` with `ovs_bond0`.

#### 2. Create the container

```sh
docker create \
  --restart=always \
  --network macvlan1 \
  --ip=192.168.1.254 \
  -p 9993:9993/udp \
  --name zerotier-gateway \
  --device=/dev/net/tun \
  --cap-add=NET_ADMIN \
  -v /volume1/docker/zerotier-gateway/zerotier-one:/var/lib/zerotier-one \
  -v /volume1/docker/zerotier-gateway/iptables:/etc/iptables \
  -v /volume1/docker/zerotier-gateway/iproute2/rt_tables:/etc/iproute2/rt_tables \
  -e NETWORK_IDS="<ZT_NETWORK_ID>" \
  -e DOCKER_HOST="<NAS_IP_eth0>" \
  -e MULTIPATH="Enabled" \
  ddeitterick/zerotier-gateway
```

#### 3. Connect the second NIC

```sh
# Create a Docker network that maps to eth1 first (if not already done)
docker network create \
  --driver macvlan \
  --gateway 172.16.x.1 \
  --subnet 172.16.x.0/24 \
  -o parent=eth1 \
  macvlan2

docker network connect macvlan2 zerotier-gateway
```

#### 4. Routing tables — map into container

File: `/volume1/docker/zerotier-gateway/iproute2/rt_tables`

```
255    local
254    main
253    default
0      unspec
101    ISP_1
102    ISP_2
```

#### 5. Route setup script — runs automatically on container start

File: `/volume1/docker/zerotier-gateway/zerotier-one/setuproutes.sh`

```sh
#!/bin/sh
IF1="eth0"
IF2="eth1"
IP1="192.168.1.x"     # DS918+ IP on LAN 1
IP2="172.16.x.x"      # DS918+ IP on LAN 2
P1="192.168.1.1"      # Gateway LAN 1
P2="172.16.x.1"       # Gateway LAN 2
P1_NET="192.168.1.0/24"
P2_NET="172.16.x.0/24"
TBL1="ISP_1"
TBL2="ISP_2"

ip route add $P1_NET dev $IF1 src $IP1 table $TBL1
ip route add default via $P1 table $TBL1
ip route add $P2_NET dev $IF2 src $IP2 table $TBL2
ip route add default via $P2 table $TBL2
ip rule add from $P1_NET table $TBL1
ip rule add from $P2_NET table $TBL2
```

#### 6. iptables NAT

File: `/volume1/docker/zerotier-gateway/iptables/rules.v4`

```
*nat
-I POSTROUTING -o zt<ZT_IFACE> -j MASQUERADE
-I POSTROUTING -o eth0 -j MASQUERADE
-I POSTROUTING -o eth1 -j MASQUERADE
COMMIT
```

---

### Known Issue: Routes lost on reboot

Routes added inside Docker are wiped on DSM reboot.

**Fix options:**
1. `setuproutes.sh` in the zerotier-one data dir — `ddeitterick/zerotier-gateway` reruns it on every container start (preferred)
2. DSM Task Scheduler → Triggered Task → Boot-up: run `ip route` / `ip rule` commands manually

---

### References

- https://docs.zerotier.com/synology/ — official Synology guide
- https://docs.zerotier.com/nas/ — general NAS page
- https://github.com/ddeitterick/zerotier-gateway — dual-NIC gateway image (source of Option B)
- https://github.com/yunifyorg/ZeroTierSynology — community SPK plugin
- https://discuss.zerotier.com/t/synology-docker-routing-table-entries-do-not-survive-reboot/4079 — reboot persistence thread
