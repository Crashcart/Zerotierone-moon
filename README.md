# Zerotierone-moon

A ZeroTier moon node (local relay) running on a Synology DS918+ via Container Manager (DSM 7+).

The DS918 sits between two firewalled networks (one port on each). ZeroTier runs on the DS918 and acts as a relay so devices on both networks can find each other over the ZeroTier overlay — without opening anything to the internet.

```
Network A  ──[eth0]──  DS918 (ZeroTier moon)  ──[eth1]──  Network B
                              UDP 9993
```

---

## Prerequisites

1. **Note the DS918's IP on each network** — you'll use one of these as the stable endpoint.
   ```bash
   ip addr show
   # or check DSM > Control Panel > Network
   ```

2. **Open UDP 9993 on the Synology firewall for both interfaces**
   - DSM > Control Panel > Security > Firewall
   - Add rule: Allow UDP port 9993, source: All (apply to both network profiles if using separate firewall profiles per interface)

3. **Create the data directory:**
   ```bash
   mkdir -p /volume1/docker/zerotierone-moon/data
   ```

---

## Deploy via Container Manager

1. Open **Container Manager** in DSM
2. Go to **Project** > **Create**
3. Name the project `zerotierone-moon`
4. Set the path to `/volume1/docker/zerotierone-moon`
5. Paste the contents of `docker-compose.yml` into the compose editor
6. Click **Next** > **Done**

The container starts and generates a ZeroTier identity automatically.

> **Note**: No router port forwarding needed — this moon is local-only.

---

## Initialize the Moon (run once)

SSH into the DS918 and run these four commands in order.

**Step 1 — Get your moon ID** (the 10-character ZeroTier node ID):
```bash
docker exec zerotierone-moon zerotier-cli info
```
Output: `200 info <MOON_ID> <version> ONLINE` — note the `<MOON_ID>`.

**Step 2 — Generate the moon config** using the DS918's local IP on whichever network your clients will use to reach it. If both networks can route to it, pick either IP — ZeroTier will accept connections on all interfaces regardless.

Replace `DS918_LOCAL_IP` with the actual IP (e.g. `192.168.1.50`):
```bash
docker exec zerotierone-moon sh -c \
  "zerotier-idtool initmoon /var/lib/zerotier-one/identity.public \
  | sed 's/\"stableEndpoints\":\[\]/\"stableEndpoints\":[\"DS918_LOCAL_IP\/9993\"]/' \
  > /var/lib/zerotier-one/moon.json"
```

**Step 3 — Sign and activate the moon file:**
```bash
docker exec zerotierone-moon sh -c \
  "cd /var/lib/zerotier-one && \
   zerotier-idtool genmoon moon.json && \
   mkdir -p moons.d && \
   mv *.moon moons.d/"
```

**Step 4 — Restart to activate:**
```bash
docker restart zerotierone-moon
```

---

## Orbit the Moon from Client Devices

On each device (on Network A or Network B) that should use this relay:
```bash
zerotier-cli orbit <MOON_ID> <MOON_ID>
```

The `<MOON_ID>` appears twice — that's correct.

Clients on Network A connect via the DS918's Network A IP.
Clients on Network B connect via the DS918's Network B IP.
Both reach the same ZeroTier daemon since the container uses host networking.

---

## Verify

On a client device, confirm the moon is visible:
```bash
zerotier-cli listpeers
```
Your moon node should appear with role `MOON`.

On the DS918, confirm the moon config is active:
```bash
docker exec zerotierone-moon zerotier-cli listmoons
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Container exits immediately | Check `/dev/net/tun` exists on host: `ls /dev/net/tun` |
| Clients can't reach the moon | Verify Synology firewall allows UDP 9993 on the relevant interface |
| Moon not showing role `MOON` on clients | Re-run Steps 2–4; confirm `moons.d/` has a `.moon` file |
| Identity lost after restart | Verify volume `/volume1/docker/zerotierone-moon/data` persists |

---

## Data Persistence

ZeroTier identity and moon config are stored at:
```
/volume1/docker/zerotierone-moon/data/
```

Back this directory up. Losing it means generating a new identity and re-orbiting all clients.
