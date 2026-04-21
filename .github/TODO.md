# 📋 Zerotierone-moon Active Task List

> 🔒 **GOVERNANCE FILE** — Protected by Rule 10 in `copilot-instructions.md`.

**Last Updated**: 2026-04-20
**Current Session**: Jazzy-Beaver — copy rules + create protected branches
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
| 6 | Copy Rules 11-12 + BRANCH_AWARE_FILES.md from alpha branch into main governance | ✅ completed | 🟠 HIGH | v2.1; hierarchy: feature→alpha→test→main |
| 7 | Create protected `test` branch on GitHub | ✅ completed | 🟠 HIGH | From main SHA; protection must be set manually in GitHub UI |
| 8 | Create branch-specific install scripts (install-alpha/beta/test.sh) + Rule 13 | ✅ completed | 🟠 HIGH | v2.2; hierarchy updated to include beta; CI enforces filename+branch |
| 9 | Create `beta` branch on GitHub | ✅ completed | 🟠 HIGH | From alpha SHA; protection must be set manually in GitHub UI |

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
