# Zerotierone-moon

A ZeroTier moon node (local relay) for Synology DS918+ running DSM 7+ via Container Manager.

The DS918 sits between two firewalled networks (one port on each). ZeroTier runs on the DS918 as a relay so devices on both networks can reach each other over the ZeroTier overlay — no internet exposure required.

```
Network A  ──[eth0]──  DS918 (ZeroTier moon)  ──[eth1]──  Network B
                              UDP 9993
```

---

## Install

SSH into the DS918, then run:

```sh
curl -fsSL https://raw.githubusercontent.com/Crashcart/Zerotierone-moon/main/install.sh -o /tmp/zt-install.sh && bash /tmp/zt-install.sh
```

The script will:
- Check prerequisites (`/dev/net/tun`, docker)
- Create the data directory
- Pull the image and start the container
- Detect your local IPs and ask which one clients should use
- Generate, sign, and activate the moon config
- Print the exact `zerotier-cli orbit` command to run on each client

---

## Update

Pull the latest image and restart, preserving your moon config:

```sh
curl -fsSL https://raw.githubusercontent.com/Crashcart/Zerotierone-moon/main/install.sh -o /tmp/zt-install.sh && bash /tmp/zt-install.sh update
```

---

## Uninstall

Stop and remove the moon node:

```sh
curl -fsSL https://raw.githubusercontent.com/Crashcart/Zerotierone-moon/main/install.sh -o /tmp/zt-install.sh && bash /tmp/zt-install.sh uninstall
```

You will be prompted before anything is deleted. The data directory (which holds the moon identity) is kept by default — delete it only if you want to fully reset.

---

## Prerequisites

Before running the install script:

1. **Open UDP 9993 on the Synology firewall** (both network interfaces)
   - DSM > Control Panel > Security > Firewall
   - Add rule: Allow UDP port 9993, source: All

2. No router port forwarding needed — this moon is local-only.

---

## Orbit clients

After install, the script prints the orbit command. Run it on every device that should use this moon:

```bash
zerotier-cli orbit <MOON_ID> <MOON_ID>
```

---

## Verify

On a client:
```bash
zerotier-cli listpeers
# Your moon should appear with role: MOON
```

On the DS918:
```bash
docker exec zerotierone-moon zerotier-cli listmoons
```

---

## Troubleshoot

| Problem | Fix |
|---------|-----|
| Script exits — `/dev/net/tun` missing | Run `modprobe tun` manually, then retry |
| Clients can't reach the moon | Check Synology firewall allows UDP 9993 on both interfaces |
| Role shows `LEAF` not `MOON` | Re-run the script — it will offer to reinstall |
| Identity lost after NAS reboot | Verify volume exists: `ls /volume1/docker/zerotierone-moon/data/` |

---

## Data

Moon identity and config are stored at:
```
/volume1/docker/zerotierone-moon/data/
```

Back this up. Losing it means generating a new identity and re-orbiting all clients.

---

## Manual setup

If you prefer to set things up step by step without the script, see the [docker-compose.yml](docker-compose.yml) in this repo and follow the inline comments in [install.sh](install.sh).
