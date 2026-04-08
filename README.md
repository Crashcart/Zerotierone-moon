# Zerotierone-moon

Run a [ZeroTier](https://www.zerotier.com/) Moon (custom root server) inside Docker to improve reliability and performance for your ZeroTier network.

## What is a ZeroTier Moon?

A **Moon** is a user-defined root server that ZeroTier clients can "orbit" to improve peer discovery and connectivity, especially on private or air-gapped networks.

## Prerequisites

- Docker ≥ 20.10
- Docker Compose ≥ 2.x
- A server with a **static public IP address** and **UDP port 9993** open in the firewall

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/Crashcart/Zerotierone-moon.git
cd Zerotierone-moon
```

### 2. Set your public IP address

```bash
export ZT_PUBLIC_IP=<your-server-public-ip>
```

Or create a `.env` file:

```
ZT_PUBLIC_IP=203.0.113.10
ZT_PORT=9993
```

### 3. Start the container

```bash
docker compose up -d
```

### 4. Get your Moon ID

```bash
docker compose logs zerotier-moon
```

Look for the line:

```
Moon ID : 000000xxxxxxxxxx
```

### 5. Orbit the moon on client nodes

Run the following on every ZeroTier client that should use your moon:

```bash
zerotier-cli orbit <moon-id> <moon-id>
```

Verify with:

```bash
zerotier-cli listmoons
```

## Configuration

| Environment Variable | Default | Description |
|---|---|---|
| `ZT_PUBLIC_IP` | *(empty)* | Public IP of your server. **Required** for a functional moon. |
| `ZT_PORT` | `9993` | UDP port ZeroTier listens on. Must be reachable from clients. |

## Persisting Data

The ZeroTier identity and moon files are stored in the `zerotier-data` Docker volume. The moon configuration (including its ID) is preserved across container restarts.

To retrieve the moon file for manual distribution:

```bash
docker cp zerotier-moon:/var/lib/zerotier-one/moons.d ./moons.d
```

## Building Manually

```bash
docker build -t zerotier-moon .
docker run -d \
  --name zerotier-moon \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --cap-add SYS_ADMIN \
  --device /dev/net/tun \
  -e ZT_PUBLIC_IP=<your-public-ip> \
  -p 9993:9993/udp \
  -v zerotier-data:/var/lib/zerotier-one \
  zerotier-moon
```

## Troubleshooting

- **Port not reachable**: Ensure UDP 9993 is allowed through your firewall/security group.
- **Moon not connecting**: Confirm `ZT_PUBLIC_IP` matches the IP clients can reach.
- **Check logs**: `docker compose logs -f zerotier-moon`

