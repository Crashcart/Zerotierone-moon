# 📋 Zerotierone-moon Active Task List

> 🔒 **GOVERNANCE FILE** — Protected by Rule 10 in `copilot-instructions.md`.

**Last Updated**: 2026-04-15
**Current Session**: Antigravity — DSM 7+ compatibility fixes
**Repository**: zerotierone-moon

---

## Active Tasks

| ID | Task | Status | Priority | Notes |
|:--:|------|--------|----------|-------|
| 1 | Add docker-compose.yml for Synology DSM 7+ Container Manager | ✅ completed | 🟠 HIGH | zyclonite/zerotier image |
| 2 | Write README.md with full moon node setup guide | ✅ completed | 🟠 HIGH | Synology-specific steps |
| 3 | Write install.sh — install / update / uninstall modes | ✅ completed | 🟠 HIGH | curl one-liner; syntax-verified |
| 4 | Merge feature branch to main | ✅ completed | 🟠 HIGH | `claude/research-install-github-qDMDt` → `main` |
| 5 | Fix install.sh for DSM 7+ shell compatibility | 🟠 in-progress | 🟠 HIGH | grep -oP, mapfile, modprobe path — all broken on BusyBox/DSM 7 |

---

## Status / Priority Legend

| Symbol | Status | | Symbol | Priority |
|--------|--------|-|--------|----------|
| ✅ | completed | | 🔴 | CRITICAL |
| 🟠 | in-progress | | 🟠 | HIGH |
| 🔵 | not-started | | 🟡 | MEDIUM |

---

Rules:
- Max 1 task `in-progress` per agent
- Update immediately on state change — no batching
- 3 statuses only: not-started, in-progress, completed
