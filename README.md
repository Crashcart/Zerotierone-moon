# Zerotierone-moon

A ZeroTier moon node (relay/root server) for Synology DSM 7+ running via Container Manager.

A moon node lets your devices find each other through your own relay instead of ZeroTier's public infrastructure. Devices "orbit" your moon and use it as a stable rendezvous point.

---

## Prerequisites

1. **Open UDP 9993 on the Synology firewall**
   - DSM > Control Panel > Security > Firewall
   - Add rule: Allow UDP port 9993, source: All

2. **Forward UDP 9993 on your router** to the Synology NAS IP

3. **Know your public IP or DDNS hostname** — this gets embedded in the moon config

4. **Create the data directory** via SSH or File Station:
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

The container will start and generate a ZeroTier identity automatically.

---

## Initialize the Moon (run once)

SSH into your Synology and run these four commands in order.

**Step 1 — Get your moon ID** (the 10-character ZeroTier node ID):
```bash
docker exec zerotierone-moon zerotier-cli info
```
Output: `200 info <MOON_ID> <version> ONLINE` — note the `<MOON_ID>`.

**Step 2 — Generate the moon config** (replace `YOUR_PUBLIC_IP` with your real IP or DDNS hostname):
```bash
docker exec zerotierone-moon sh -c \
  "zerotier-idtool initmoon /var/lib/zerotier-one/identity.public \
  | sed 's/\"stableEndpoints\":\[\]/\"stableEndpoints\":[\"YOUR_PUBLIC_IP\/9993\"]/' \
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

On each device you want to use this moon (Linux, macOS, Windows, etc.):
```bash
zerotier-cli orbit <MOON_ID> <MOON_ID>
```

The `<MOON_ID>` appears twice — that's correct.

---

## Verify

Check that your moon is visible to a client:
```bash
zerotier-cli listpeers
```

Your moon node should appear with role `MOON`.

To confirm the moon is running on the Synology:
```bash
docker exec zerotierone-moon zerotier-cli listmoons
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Container exits immediately | Ensure `/dev/net/tun` exists: `ls /dev/net/tun` on the Synology host |
| Moon not visible to clients | Verify UDP 9993 is reachable: `nc -vzu YOUR_PUBLIC_IP 9993` |
| Identity lost after restart | Check the volume mount — `/volume1/docker/zerotierone-moon/data` must persist |
| `listpeers` shows no MOON | Re-run Steps 2–4 and confirm `moons.d/` contains a `.moon` file |

---

## Data Persistence

ZeroTier identity and config are stored at:
```
/volume1/docker/zerotierone-moon/data/
```

Back this directory up. Losing it means generating a new identity and re-orbiting all clients.
