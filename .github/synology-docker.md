# Running ZeroTier One Moon on Synology NAS with Docker

This guide explains how to deploy a ZeroTier One Moon (private root/bridge server) on a Synology NAS using the built-in **Container Manager** (formerly Docker) application available in Synology DiskStation Manager (DSM).

> **Reference:** [Synology DSM – Container Manager (Docker) feature page](https://www.synology.com/en-us/dsm/feature/docker)

---

## Prerequisites

- A Synology NAS running **DSM 7.0** or later
- **Container Manager** (Docker) installed from the Synology Package Center
- SSH access enabled on the NAS (optional, for CLI setup)
- A static IP or DDNS hostname for your NAS

---

## 1. Install Container Manager

1. Open **Package Center** in DSM.
2. Search for **Container Manager**.
3. Click **Install** and follow the prompts.

> Container Manager is available on most Synology models with an Intel or AMD x86_64 processor. Check the [Synology compatibility list](https://www.synology.com/en-us/dsm/packages/ContainerManager) to confirm your model is supported.

---

## 2. Create the Docker Network (optional)

For better isolation, create a dedicated bridge network via the Container Manager UI:

1. Open **Container Manager** → **Network** → **Add**.
2. Name it `zerotier-net` and select **Bridge** as the driver.
3. Click **Apply**.

---

## 3. Pull the ZeroTier One Image

1. Open **Container Manager** → **Registry**.
2. Search for `zerotier/zeronsd` or `zerotier/zerotier-one` (use `zerotier/zerotier-one` for a standard node/moon).
3. Select the image and click **Download** to pull the `latest` tag.

Alternatively, pull via SSH:

```bash
docker pull zerotier/zerotier-one:latest
```

---

## 4. Prepare the Moon Configuration

Before starting the container, generate the Moon configuration on your NAS (via SSH or a one-off container):

```bash
# Create a persistent data directory on the NAS
mkdir -p /volume1/docker/zerotier-one

# Run a temporary container to generate the moon identity
docker run --rm \
  -v /volume1/docker/zerotier-one:/var/lib/zerotier-one \
  zerotier/zerotier-one \
  zerotier-idtool generate /var/lib/zerotier-one/identity.secret /var/lib/zerotier-one/identity.public
```

Generate the Moon definition and sign it:

```bash
# Generate the moon.json template (replace <YOUR_PUBLIC_IP> with your NAS public IP)
docker run --rm \
  -v /volume1/docker/zerotier-one:/var/lib/zerotier-one \
  zerotier/zerotier-one \
  bash -c "cd /var/lib/zerotier-one && \
    zerotier-idtool initmoon identity.public | \
    sed 's/\"stableEndpoints\": \[\]/\"stableEndpoints\": [\"<YOUR_PUBLIC_IP>\/9993\"]/' \
    > moon.json && \
    zerotier-idtool genmoon moon.json"
```

This produces a `000000<moonID>.moon` file inside `/volume1/docker/zerotier-one/`.

---

## 5. Run the Moon Container via Container Manager UI

1. Open **Container Manager** → **Container** → **Create**.
2. **Image:** select `zerotier/zerotier-one:latest`.
3. Under **Advanced Settings**:
   - **Volume:** add `/volume1/docker/zerotier-one` → `/var/lib/zerotier-one`
   - **Network:** select `Host` mode (required so ZeroTier can manage network interfaces) **or** use bridge mode and map UDP port `9993`.
   - **Environment:** add `TZ` set to your timezone (e.g., `America/New_York`).
   - **Capabilities:** enable `NET_ADMIN` and `SYS_MODULE` (required for ZeroTier to manage virtual interfaces).
4. Set **Restart Policy** to **Always**.
5. Click **Apply** to start the container.

---

## 6. Run the Moon Container via Docker CLI (SSH)

```bash
docker run -d \
  --name zerotier-moon \
  --restart always \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --device /dev/net/tun \
  -v /volume1/docker/zerotier-one:/var/lib/zerotier-one \
  zerotier/zerotier-one:latest
```

---

## 7. Open the Firewall Port

Ensure UDP port **9993** is open on your Synology NAS and your router (port forwarding to the NAS LAN IP):

1. In DSM, go to **Control Panel** → **Security** → **Firewall**.
2. Create a rule to allow **UDP port 9993** from any source.
3. In your router, add a port-forwarding rule: **UDP 9993** → NAS LAN IP.

---

## 8. Distribute the Moon File to Clients

Copy the generated `000000<moonID>.moon` file to each ZeroTier client device:

| OS | Moon file path |
|----|----------------|
| Linux | `/var/lib/zerotier-one/moons.d/` |
| macOS | `/Library/Application Support/ZeroTier/One/moons.d/` |
| Windows | `C:\ProgramData\ZeroTier\One\moons.d\` |

Then restart the ZeroTier service on each client, or run:

```bash
zerotier-cli orbit <moonID> <moonID>
```

---

## 9. Verify Connectivity

On a ZeroTier client, verify the moon is reachable:

```bash
zerotier-cli listmoons
```

You should see your moon listed with `timestamp` and `updatesMustBeSignedBy` populated.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Container fails to start | Ensure `/dev/net/tun` exists on the NAS (`ls /dev/net/tun`) |
| Moon not listed on clients | Confirm UDP 9993 is open on NAS firewall and router NAT |
| `NET_ADMIN` capability error | Some Synology models restrict kernel capabilities; try running in `privileged` mode as a last resort |
| Container Manager not available | Your NAS model may not support Docker; check the [compatibility list](https://www.synology.com/en-us/dsm/packages/ContainerManager) |

---

## References

- [Synology Container Manager (Docker) – DSM Feature](https://www.synology.com/en-us/dsm/feature/docker)
- [ZeroTier One – GitHub](https://github.com/zerotier/ZeroTierOne)
- [ZeroTier Moon (Root Server) Documentation](https://docs.zerotier.com/moons)
