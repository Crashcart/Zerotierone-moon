# Repository Configuration — Zerotierone-moon

> **Purpose**: Project-specific settings for AI agents. Read this alongside `copilot-instructions.md`.  
> **Last Updated**: 2026-04-12  
> 🔒 **GOVERNANCE FILE** — Protected by Rule 10 in `copilot-instructions.md`. Follow full workflow when editing.

---

## PROJECT OVERVIEW

**Name**: Zerotierone-moon  
**Type**: ZeroTier Moon Node (Docker-based)  
**Description**: A ZeroTier moon node (root server) that acts as a bridge/relay for ZeroTier networks. Enables devices to connect to a self-hosted ZeroTier root instead of relying on ZeroTier's public infrastructure.  
**Installation**: Runtipi app store (crashcart/tipistore)

---

## COMMANDS

| Action | Command |
|--------|---------|
| **Start** | `docker-compose up -d` |
| **Stop** | `docker-compose down` |
| **View logs** | `docker-compose logs -f` |
| **Enter container** | `docker exec -it zerotierone-moon bash` |
| **Show ZT identity** | `docker exec zerotierone-moon zerotier-cli info` |
| **Init moon** | `docker exec zerotierone-moon zerotier-idtool initmoon /var/lib/zerotier-one/identity.public` |
| **Orbit moon** | `zerotier-cli orbit <moonID> <moonID>` |

---

## FILES TO MONITOR

### Governance (read first every session)
| File | Purpose |
|------|---------|
| `.github/copilot-instructions.md` | Universal agent rules |
| `.github/REPO_CONFIG.md` | This file — project-specific config |
| `.github/TODO.md` | Active task list |
| `.github/PLANNING.md` | Planning, context, and handoff notes |

### Core Application
| File | Description | Conflict Risk |
|------|-------------|:------------:|
| `docker-compose.yml` | Container definitions + capabilities | 🟡 MEDIUM |
| `Dockerfile` | Container image (if custom) | 🟡 MEDIUM |
| `README.md` | Primary documentation | 🟢 LOW |

---

## DOCKER REQUIREMENTS

ZeroTier One requires elevated privileges to manage network interfaces:

```yaml
cap_add:
  - NET_ADMIN
  - SYS_ADMIN
devices:
  - /dev/net/tun
ports:
  - "9993:9993/udp"
volumes:
  - zerotier-data:/var/lib/zerotier-one
```

---

## HIGH-CONFLICT FILES

| File | Risk | Why |
|------|:----:|-----|
| `.github/copilot-instructions.md` | 🔴 HIGH | Multiple agents update rules |
| `docker-compose.yml` | 🟡 MEDIUM | Service configs updated in parallel |

---

## PROJECT CONVENTIONS

- Moon node identity is stored in `/var/lib/zerotier-one/` (must persist across restarts)
- Port `9993/udp` is ZeroTier's default — do not change without documentation
- The app should be installable via Runtipi/tipistore with minimal manual steps
