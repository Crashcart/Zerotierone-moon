# 🗺️ Zerotierone-moon Planning & Coordination

> 🔒 **GOVERNANCE FILE** — Protected by Rule 10 in `copilot-instructions.md`. Follow full workflow when editing.

**Last Updated**: 2026-05-26
**Document Purpose**: Centralized planning for multi-agent coordination, architectural decisions, and project context

---

## 🎯 Active Initiatives

### IPv6 ip6tables + TCP MSS Clamping

**Status**: ✅ Complete — merged to dev (2026-05-20)
**Branch**: `claude/add-synology-zerotier-todo-B0Tup`

**Approach**: Two networking gaps remain after the polished-product merge:
1. `ip6tables` is installed in the Docker image but never applied — no `rules.v6` exists and `entrypoint.sh` never calls `ip6tables-restore`. IPv6 FORWARD chain is unmanaged.
2. TCP MSS clamping is absent from the mangle table. When the ZeroTier overlay MTU is smaller than the physical NIC MTU, TCP sessions forwarded through the gateway can silently stall (path-MTU black hole).

**Decisions Log**:
- [2026-05-20] Phase 0 complete: re-imported `copilot-instructions.md` per new goal; re-read all governance files
- [2026-05-20] MSS clamping: add `-A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu` to `*mangle` in both `config/rules.v4` template and `install.sh` generated copy
- [2026-05-20] IPv6: create `config/rules.v6` template (FORWARD + ICMPv6, no NAT); `install.sh` generates data-dir copy with real interface names; `entrypoint.sh` applies via `ip6tables-restore`
- [2026-05-20] **REPO RULE (user-authorized, permanent)**: Always push to `dev` and auto-merge PRs to `dev`. This overrides copilot-instructions.md Rule #3 (no auto-merge) and Rule #11 (target alpha) for this repository. Branch hierarchy is `dev → alpha → beta → main`; promotion to alpha/beta/main requires explicit human instruction.
- [2026-05-20] AI-rules v1.9.0 imported. New active rules: COMPANY IDENTITY; RULE 15 COMPLIANCE ENFORCEMENT; RULE 16 HIRING APPROVAL. Approved roster: 30 roles.
- [2026-05-21] AI-rules v1.14.1 imported. New rules: RULE 17 USER CHANGE AUTHORITY (user holds sole authority over rule changes; silence ≠ approval) [NON-NEGOTIABLE]; RULE 18 SEPARATION OF DUTIES (no mixing security-* with implementation roles) [NON-NEGOTIABLE]. New role: HIRING MANAGER (HR/Jordan Reyes) — all hiring gaps now route to HR first, not PM; HR does algebraic check and presents to CEO. New employee: AUDIO/STREAMING ENGINEER (Kai Nakamura) — scoped to RP-Music-Radio and MusicBot only, not applicable here. CEO SESSION EXCLUSIVITY: sub-agent Claude defaults to PM. agents/registry.json is now the authoritative roster.
- [2026-05-24] AI-rules v1.25.0 imported. New rules: RULE 19 SESSION-START CHECK (version verification on every load; auto-bootstrap missing files; Role Announcement is NON-NEGOTIABLE) [v1.20.1]; RULE 20 MANAGER HANDOFF & BETA DELIVERY STANDARD (outgoing role must name incoming + state completed + remaining + context + target; incoming must acknowledge; Beta = runs end-to-end, demonstrable, gaps documented) [v1.24.0]. New team members: AI COMPLIANCE ENGINEER (Priya Nair, Bangalore) — session-start compliance and behavioral regression; RULE ARCHITECT (Vera Okonkwo) — rule drafting and version governance, no self-approval authority. Hiring process updated: 7–10 candidates, global distribution, code test before interviews (10/20 pass threshold), current incumbent as Candidate #1 in replacement pools. Full roster: 33 roles, 27+ confirmed hires. Rules v1.15–v1.25 also added web-design standards, HR rehire protocol, and software-factory guide (not applicable to this repo).
- [2026-05-24] AI-rules v1.25.1 imported. Patch: session-start enforcement hook. No new rules or roles vs v1.25.0.
- [2026-05-26] Auto-update feature + shared compose lib shipped (PR #29 merged to dev). Key changes: lib/compose.sh shared generate_compose(); update.sh fixed branch-switch conflict (git checkout -- docker-compose.yml before checkout); compose regenerated on every update; zmoon autoupdate command added; AUTO_UPDATE/AUTO_UPDATE_BRANCH in .env; 53 tests.
- [2026-05-26] Gold-build audit (PR #30 merged to dev). Defects fixed: build.yml/test.yml now generate docker-compose.yml from lib/compose.sh in CI (file is gitignored — was failing on every push); update.sh regenerates compose unconditionally (not only on --branch); zmoon help range fixed (sed 3,19p); lib/compose.sh added to shellcheck/tests; README Step 5 replaced stale ddeitterick compose snippet; rules.v4 README snippet added TCPMSS; Updating section added old-install migration + auto-update DSM instructions. 55 tests passing.
- [2026-05-26] Research audit: corrected DDNS bug — ZT_PUBLIC_ENDPOINT was documented as accepting DDNS hostname but stableEndpoints requires bare IP. Fixed .env.example, install.sh prompt, README Step 7, RESEARCH.md. Also corrected RESEARCH.md buffer size (25 MB → 8 MB).
- [2026-05-20] Phase 3 complete: DEVELOPER subagent added IPv6 *mangle TCPMSS to rules.v6; PM added install.sh parity and 2 new test assertions (49 total)
- [2026-05-20] IPv6 MSS clamping PR #18 open on dev — awaiting human review per Rule #3
- [2026-05-20] Governance note: AI-rules v1.5.1 imported (claude-behavior.md); previous session-specific rules erased; copilot-instructions.md + claude-behavior.md now govern
- [2026-05-20] Governance conflict flagged: copilot-instructions.md Rule #11 says target `alpha` for all PRs, but `alpha` is far behind `dev`; continuing to target `dev` until human resolves

---

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
