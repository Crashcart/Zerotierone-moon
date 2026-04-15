# Zerotierone-moon

A ZeroTier moon node (local relay) for Synology DS918+ running DSM 7+ via Container Manager.

The DS918 sits between two firewalled networks (one port on each). ZeroTier runs on the DS918 as a relay so devices on both networks can reach each other over the ZeroTier overlay — no internet exposure required.

```
Network A  ──[eth0]──  DS918 (ZeroTier moon)  ──[eth1]──  Network B
                              UDP 9993
```

---

## Install

SSH into the DS918 as root, then run:

```sh
curl -fsSL https://raw.githubusercontent.com/Crashcart/Zerotierone-moon/main/install.sh -o /tmp/zt-install.sh && sudo bash /tmp/zt-install.sh
```

The script will:
- Check prerequisites (`/dev/net/tun`, docker, root)
- Create the data directory
- Pull the image and start the container
- Detect your local IPs and ask which one clients should use
- Generate, sign, and activate the moon config
- Print the exact `zerotier-cli orbit` command to run on each client

### Fully automatic install

Skip all prompts — auto-selects the first detected IP:

```sh
curl -fsSL https://raw.githubusercontent.com/Crashcart/Zerotierone-moon/main/install.sh -o /tmp/zt-install.sh && sudo bash /tmp/zt-install.sh --auto --network <your_network_id>
```

Or specify the endpoint IP directly:

```sh
curl -fsSL https://raw.githubusercontent.com/Crashcart/Zerotierone-moon/main/install.sh -o /tmp/zt-install.sh && sudo bash /tmp/zt-install.sh --auto --network abcdef1234567890 --ip 10.0.1.50
```

### Options

| Flag | Description |
|------|-------------|
| `--auto`, `-a` | Fully unattended — auto-select IP, skip all prompts |
| `--network <id>` | Join this ZeroTier network (16-char hex ID) |
| `--ip <addr>` | Use this IP as the moon's stable endpoint |
| `--force`, `-f` | Force reinstall if container already exists |
| `--purge` | (uninstall only) Also delete the data directory |
| `--help`, `-h` | Show usage |

---

## Update

Pull the latest image and restart, preserving your moon config:

```sh
curl -fsSL https://raw.githubusercontent.com/Crashcart/Zerotierone-moon/main/install.sh -o /tmp/zt-install.sh && sudo bash /tmp/zt-install.sh update
```

---

## Uninstall

Stop and remove the moon node:

```sh
curl -fsSL https://raw.githubusercontent.com/Crashcart/Zerotierone-moon/main/install.sh -o /tmp/zt-install.sh && sudo bash /tmp/zt-install.sh uninstall
```

You will be prompted before anything is deleted. The data directory (which holds the moon identity) is kept by default. To remove everything including the data directory:

```sh
curl -fsSL https://raw.githubusercontent.com/Crashcart/Zerotierone-moon/main/install.sh -o /tmp/zt-install.sh && sudo bash /tmp/zt-install.sh uninstall --purge
```

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
