# 🗺️ Zerotierone-moon Planning & Coordination

> 🔒 **GOVERNANCE FILE** — Protected by Rule 10 in `copilot-instructions.md`. Follow full workflow when editing.

**Last Updated**: 2026-05-12
**Document Purpose**: Centralized planning for multi-agent coordination, architectural decisions, and project context

---

## 🎯 Active Initiatives

### Polished Product: `zmoon` CLI + Test Suite + Critical iptables Fix

**Status**: ✅ Complete — merged to dev (2026-05-17)
**Branch**: `claude/add-synology-zerotier-todo-B0Tup`

**Approach**: Consolidate the deployment toolkit into a single polished `zmoon`
CLI, add a dependency-free test suite + CI wiring, and fix bugs found by a full
audit — most critically an illegal `-i` match in nat/POSTROUTING that aborted
the entire iptables ruleset on every real DSM host.

**Decisions Log**:
- [2026-05-17] **CRITICAL**: `-A POSTROUTING -i zt+ ...` is invalid iptables (POSTROUTING runs post-routing and cannot match input interface). `iptables-restore` is atomic, so this one line silently aborted NOTRACK + FORWARD + MASQUERADE on every DSM host. Replaced with a mangle/FORWARD `MARK 0x2a` matched by `nat/POSTROUTING -m mark` — the documented, correct way to scope MASQUERADE to forwarded ZT traffic.
- [2026-05-17] Added `zmoon` unified CLI (install/update/status/doctor/peers/moon-id/backup/restore/logs/version); install/update delegate to existing scripts to preserve the documented manual path.
- [2026-05-17] `zmoon doctor` automates the STABILITY.md diagnostic checklist into PASS/WARN/FAIL with a non-zero exit code (cron/Task-Scheduler friendly).
- [2026-05-17] Added `tests/run.sh` pure-bash suite (no bats); wired into `test.yml`; added `zmoon`+`tests/run.sh` to `lint.yml` ShellCheck.
- [2026-05-17] Made every shell script 100% ShellCheck-clean at default severity (replaced `ls`-globs with bash nullglob arrays, split SC2155, restructured SC2015/SC2164) — CI lint was previously red on `update.sh` SC2012.
- [2026-05-17] Fixed `ip rule del table` flush (deleted only one rule/call → loop), `.gitignore` missing `.env`, entrypoint process-death detection, unbounded backups, macvlan `--ip-range` scoping, ZT_NETWORK_ID validation.

---

### Stability & Throughput Improvements + .github Audit

**Status**: ✅ Complete — merged to dev (PR #11, 2026-05-12)
**Branch**: `claude/add-synology-zerotier-todo-B0Tup`

**Approach**: Implement all 7 stability fixes and 5 throughput improvements documented in
`STABILITY.md`, plus audit and update all `.github/` files for correctness.

**Decisions Log**:
- [2026-05-12] Alpine 3.19 → 3.21 in Dockerfile — newer zerotier-one avoids 1.14.0 Synology bug
- [2026-05-12] Added NET_RAW cap — required for iptables raw table (NOTRACK rules)
- [2026-05-12] Added NOTRACK in rules.v4 — removes ZeroTier UDP from conntrack (fixes 30s timeout cutouts)
- [2026-05-12] Added 25 MB UDP socket buffers in compose sysctls and host sysctl.conf
- [2026-05-12] Added Docker healthcheck — auto-restarts container if daemon hangs (known DSM 7.2 issue)
- [2026-05-12] Added local.conf — pins port 9993, enables TCP fallback, blacklists Docker interfaces
- [2026-05-12] Added conntrack timeout 300s and fq qdisc in entrypoint.sh
- [2026-05-12] Added ethtool NIC offload (GRO/TSO/GSO) in install.sh
- [2026-05-12] Added update.sh with --branch flag for safe branch upgrades
- [2026-05-12] Fixed install.sh to generate full compose with all stability settings + copy local.conf
- [2026-05-12] Updated all CI workflows to target correct branches (dev/alpha/beta/main, removed stale test branch)
- [2026-05-12] Updated build.yml checks for custom zerotier-moon image and macvlan networking

---

### DSM 7+ Shell Compatibility Fix — install.sh

**Status**: ✅ Complete — merged in PR #7
**Branch**: `fix/dsm7-install-compat`

**Approach**: Audit `install.sh` for DSM 7+ BusyBox compatibility issues and fix all breakage. DSM 7 ships BusyBox utilities alongside GNU coreutils — scripts must not rely on GNU-only features (`grep -P`, `mapfile`) or hardcoded kernel module paths.

**Decisions Log**:
- [2026-04-15] Replaced `grep -oP '(?<=inet )...'` with `awk '/inet / {split($2, a, "/"); print a[1]}'` — PCRE lookbehind requires GNU grep with `-P`, which BusyBox grep doesn't support
- [2026-04-15] Replaced `mapfile -t IPS < <(...)` with `while IFS= read -r` loop + here-string — `mapfile` is bash 4+ only; here-string (`<<<`) works in bash 3+ which DSM 7 ships
- [2026-04-15] Added `ifconfig` fallback for IP detection — some DSM builds have limited `ip` command
- [2026-04-15] Fixed `insmod /lib/modules/tun.ko` → dynamic `find /lib/modules -name 'tun.ko*'` — DSM 7 stores kernel modules in versioned subdirectories, not at root
- [2026-04-15] Cleaned all `&>/dev/null 2>&1` → `>/dev/null 2>&1` — the `&>` bashism doubled stderr redirect redundantly

### synology-docker.md Image Reference Fix

**Status**: ✅ Complete — committed on `claude/zerotier-synology-setup-Uwn2L`

**Decisions Log**:
- [2026-04-19] Replaced all `zerotier/zerotier-one` references with `zyclonite/zerotier` — the official upstream image is not pre-built for ARM/multi-arch; `zyclonite/zerotier` is the image actually used in install.sh and docker-compose.yml

### Initial Project Setup — Moon Node for Synology DSM 7+

**Status**: ✅ Complete — merged to main
**Branch**: `claude/research-install-github-qDMDt`

**Approach**: Deploy ZeroTier One as a pure relay (moon node) via Synology Container Manager using the `zyclonite/zerotier` Docker image. `network_mode: host` used to avoid UDP NAT issues on DSM 7.

**Decisions Log**:
- [2026-04-14] Used `zyclonite/zerotier` over building custom image — well-tested on Synology, actively maintained
- [2026-04-14] `network_mode: host` chosen over bridge — avoids port mapping complexity for UDP 9993
- [2026-04-14] Volume at `/volume1/docker/zerotierone-moon/data` — standard DSM 7 docker data location
- [2026-04-14] No Runtipi packaging — user is on Synology Container Manager directly
- [2026-04-14] `install.sh` script chosen over GUI guide — moon init requires CLI regardless; one-liner reduces error surface
- [2026-04-14] stableEndpoints set interactively from detected local IPs — NAS is dual-homed, user picks the right interface
- [2026-04-14] Moon config generated inline (no temp files left behind); container restarted to activate

---

## 🏗️ Architecture Decisions

_(none yet)_

---

## 🤝 Handoff Notes

**For next agent**:
- DSM 7+ compatibility fix is merged (PR #7). No further action needed on install.sh compatibility.
- Project now uses a **custom `zerotier-moon` image** built from `Dockerfile` (Alpine 3.21) — NOT `zyclonite/zerotier` or `zerotier/zerotier-synology`.
- **Branch hierarchy**: `dev → alpha → beta → main`. All automated claude/** PRs target `dev`. Promotions to alpha/beta/main require explicit human instruction.
- Stability improvements are complete — see `STABILITY.md` and `RESEARCH.md` for details.
- CI workflows updated: all now target `dev/alpha/beta/main` branches; stale `test` branch reference removed.
- `install.sh` now generates a fully-featured docker-compose.yml including NET_RAW, healthcheck, sysctls, and local.conf mount.

---

## 📁 Key File Reference

| File | Purpose |
|------|---------|
| `.github/copilot-instructions.md` | Enterprise agent rules |
| `.github/TODO.md` | Active + frozen task tracking |
| `.github/PLANNING.md` | This file |
| `.github/REPO_CONFIG.md` | Project-specific configuration |
