# Zerotierone-moon

A **ZeroTier Moon** (custom root server) running in Docker on a **Synology DS918+** NAS. A Moon improves reliability and speed for your ZeroTier network by giving clients a stable relay point on your own infrastructure.

---

## Prerequisites

| Requirement | Details |
|---|---|
| Synology DS918+ | DSM 7 or later |
| Docker | Installed from Synology Package Center |
| SSH access | Enabled in DSM → Control Panel → Terminal & SNMP |
| Public IP | A static or DDNS address reachable from the internet on **UDP 9993** |

---

## Quick Start

### 1 – SSH into your NAS

```sh
ssh admin@<NAS-IP>
sudo -i
```

### 2 – Clone this repository

```sh
mkdir -p /volume1/docker
cd /volume1/docker
git clone https://github.com/Crashcart/Zerotierone-moon.git
cd Zerotierone-moon
```

### 3 – Run the setup script

```sh
chmod +x setup.sh
ZEROTIER_MOON_PUBLIC_IP=<YOUR_PUBLIC_IP> bash setup.sh
```

Replace `<YOUR_PUBLIC_IP>` with your NAS's public-facing IP address (or DDNS hostname).  
If the variable is not set the script will prompt you for it interactively.

The script will:

1. Load and persist the `tun` kernel module required by ZeroTier.
2. Create the persistent storage directory `/volume1/docker/zerotier-moon`.
3. Pull the `seedgou/zerotier-moon` Docker image and start the container.
4. Wait for the ZeroTier identity to be generated.
5. Print the **Moon ID** and the orbit command for your clients.

---

## Directory Layout

```
/volume1/docker/zerotier-moon/   ← persistent ZeroTier data
├── identity.public               ← public node identity (Moon ID)
├── identity.secret               ← private key  ⚠️ keep secret
└── moons.d/
    └── 000000<moonid>.moon       ← generated Moon file
```

---

## Orbiting the Moon (Clients)

### Option A – `zerotier-cli orbit` (easiest)

Run the following on every ZeroTier client that should use this Moon:

```sh
zerotier-cli orbit <MOON_ID> <MOON_ID>
```

Verify the Moon is visible:

```sh
zerotier-cli peers
# Should show a MOON entry for your server
```

### Option B – Copy the `.moon` file

1. Copy the generated file from the NAS:

```sh
scp admin@<NAS-IP>:/volume1/docker/zerotier-moon/moons.d/000000*.moon ./
```

2. Place it in the client's `moons.d` directory:

| OS | Path |
|---|---|
| Linux | `/var/lib/zerotier-one/moons.d/` |
| macOS | `/Library/Application Support/ZeroTier/One/moons.d/` |
| Windows | `C:\ProgramData\ZeroTier\One\moons.d\` |

3. Restart the ZeroTier service on the client.

---

## Joining the ZeroTier Network

Once your Moon is running, join your ZeroTier network ID as usual:

```sh
zerotier-cli join <NETWORK_ID>
```

Approve the device in [my.zerotier.com](https://my.zerotier.com) (or your self-hosted controller).

---

## Docker Compose Reference

The [`docker-compose.yml`](docker-compose.yml) file uses the following key settings:

| Option | Value | Purpose |
|---|---|---|
| `image` | `seedgou/zerotier-moon:latest` | ZeroTier Moon Docker image |
| `restart` | `unless-stopped` | Auto-restart after reboots |
| `ports` | `9993/udp` | ZeroTier control plane port |
| `volumes` | `/volume1/docker/zerotier-moon` | Persistent identity & config |
| `cap_add` | `NET_ADMIN`, `SYS_ADMIN` | Required for virtual networking |
| `devices` | `/dev/net/tun` | Kernel TUN device |

Set the public IP by exporting `ZEROTIER_MOON_PUBLIC_IP` or placing it in a `.env` file in the same directory as `docker-compose.yml`.

---

## Useful Commands

```sh
# View Moon container logs
docker logs -f zerotier-moon

# Check ZeroTier status inside the container
docker exec zerotier-moon zerotier-cli status

# List peers known to the Moon
docker exec zerotier-moon zerotier-cli peers

# Stop the Moon
docker compose down

# Update the image
docker compose pull && docker compose up -d
```

---

## Troubleshooting

### `/dev/net/tun` not found

Some DSM updates reset the kernel module state. Re-run the TUN boot script:

```sh
/usr/local/etc/rc.d/tun.sh
```

Or simply reboot the NAS – the boot script runs automatically on startup.

### Container exits immediately

Check logs for details:

```sh
docker logs zerotier-moon
```

Ensure `NET_ADMIN` and `SYS_ADMIN` capabilities are granted and that `/dev/net/tun` exists before starting.

### Clients cannot reach the Moon

- Confirm **UDP 9993** is open in your router/firewall and forwarded to the NAS.
- Verify `ZEROTIER_MOON_PUBLIC_IP` matches the actual public IP seen by the internet.

---

## Security Notes

- Keep `/volume1/docker/zerotier-moon/identity.secret` private; it is the cryptographic identity of your Moon node.
- Do **not** commit the `.env` file or the `identity.secret` file to version control.
- Restrict SSH access and use key-based authentication on the NAS.
