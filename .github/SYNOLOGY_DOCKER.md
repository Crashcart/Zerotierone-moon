# Synology Container Manager — Reference Notes

Source: https://www.synology.com/en-us/dsm/feature/docker

> Container Manager is Synology's Docker runtime for DSM 7+.
> It replaces the older "Docker" package. DS918+ (Intel J3455, x86_64) is fully supported.

---

## UI Overview

| Tab | What it does |
|-----|-------------|
| **Overview** | Live CPU / RAM / network stats across all running containers |
| **Container** | Create, start, stop, restart, delete, and edit individual containers |
| **Image** | Pull images from Docker Hub or private registries; check for updates |
| **Registry** | Connect to Docker Hub, GHCR, or self-hosted registries |
| **Network** | Create and manage Docker networks; assign networks to containers |
| **Project** | Import and run Docker Compose files (multi-container projects) — DSM 7.2+ |
| **Log** | Centralised log viewer across all containers |

---

## Network Drivers

| Driver | Notes |
|--------|-------|
| `bridge` | Default. NAT through the NAS host IP; requires port mapping. |
| `host` | Container shares the host network stack. No port mapping needed. Used by ZeroTier Option A. |
| `macvlan` | Gives the container its own real LAN IP. **Must be created via CLI (SSH)** — the UI does not expose all required parameters (subnet, gateway, parent interface). Once created, it appears in the Network tab and can be assigned to containers from the GUI. |
| Custom bridge | Creatable from the Network tab UI. |

### macvlan — Important Caveats

- **Must be created via SSH:** `docker network create --driver macvlan --subnet ... --gateway ... -o parent=eth0 macvlan-lan1`
- **Does not survive DSM reboot** — the network definition is lost and containers lose connectivity. Fix: re-run the `docker network create` command at boot via DSM Task Scheduler (Control Panel → Task Scheduler → Triggered Task → Boot-up).
- **Host ↔ container isolation:** macvlan containers cannot reach the NAS host directly, and the host cannot reach them. This is a kernel limitation. Workaround: create a secondary macvlan interface on the host (requires SSH).
- **Do not re-edit macvlan containers in the GUI** — Container Manager will silently drop advanced network config (static IPs, custom routes) when saving changes through the UI. Manage macvlan containers exclusively via Compose or CLI.

---

## Project Tab (Docker Compose) — DSM 7.2+

- Create a Project by uploading a `docker-compose.yml` (or pasting inline)
- Supports `up`, `down`, `pull`, `restart` via UI buttons
- Compose projects persist across DSM updates; containers created directly in the GUI may not
- **Volume paths must be absolute and use `/volume1/...`** — relative paths fail silently
- Environment variables can be injected via the UI or a `.env` file in the same directory

**How to deploy this repo's compose file via the UI:**
1. Container Manager → Project → Create
2. Name the project (e.g. `zerotier-moon`)
3. Set path to `/volume1/docker/zerotier` (where install.sh places files)
4. Upload `docker-compose.yml` or paste contents
5. Click Next / Apply

---

## Relevant Capabilities for ZeroTier Moon

| Requirement | Container Manager Support |
|-------------|--------------------------|
| `/dev/net/tun` device | ✓ via `devices:` in compose |
| `NET_ADMIN` capability | ✓ via `cap_add:` in compose |
| `SYS_ADMIN` capability | ✓ via `cap_add:` in compose |
| `--net=host` | ✓ supported |
| macvlan networks | ✓ but CLI-only creation |
| Dual-NIC (eth0 + eth1) | ✓ via two separate macvlan networks |
| Restart on boot | ✓ `restart: always` in compose |
| Docker Compose v2 | ✓ DSM 7.2+ |
| Build from Dockerfile | ✓ `docker build` via SSH; or pre-built image |

---

## DS918+ Specific Notes

- **Architecture:** Intel Celeron J3455 (Apollo Lake), x86_64
- **Container Manager:** Fully supported on DSM 7.x
- **RAM:** 4 GB DDR3L (expandable to 8 GB) — sufficient for ZeroTier + moon
- **NICs:** 2x RJ-45 1GbE — appears as `eth0` and `eth1` (or `ovs_bond0` if Link Aggregation is enabled)
- **Link Aggregation:** If active, both ports merge into `ovs_bond0`. Disable for independent dual-network ZeroTier access.
- **SSH:** Disabled by default in DSM 7. Enable via Control Panel → Terminal & SNMP → Enable SSH service.

---

## References

- https://www.synology.com/en-us/dsm/feature/docker — feature overview
- https://kb.synology.com/en-us/DSM/help/ContainerManager/docker_overview?version=7 — UI overview
- https://kb.synology.com/en-us/DSM/help/ContainerManager/docker_project?version=7 — Compose/Project tab
- https://kb.synology.com/en-us/DSM/help/ContainerManager/docker_desc?version=7 — Container Manager description
- https://www.synology.com/en-us/releaseNote/ContainerManager — release notes
- https://community.synology.com/enu/forum/1/post/133969 — macvlan upstart/boot script thread
