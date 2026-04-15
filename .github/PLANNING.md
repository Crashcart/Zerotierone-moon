# 🗺️ Zerotierone-moon Planning & Coordination

> 🔒 **GOVERNANCE FILE** — Protected by Rule 10 in `copilot-instructions.md`. Follow full workflow when editing.

**Last Updated**: 2026-04-15
**Document Purpose**: Centralized planning for multi-agent coordination, architectural decisions, and project context

---

## 🎯 Active Initiatives

### DSM 7+ Shell Compatibility Fix — install.sh

**Status**: Phase 2 — Implementation complete, pending review
**Branch**: _(local edit — needs feature branch)_

**Approach**: Audit `install.sh` for DSM 7+ BusyBox compatibility issues and fix all breakage. DSM 7 ships BusyBox utilities alongside GNU coreutils — scripts must not rely on GNU-only features (`grep -P`, `mapfile`) or hardcoded kernel module paths.

**Decisions Log**:
- [2026-04-15] Replaced `grep -oP '(?<=inet )...'` with `awk '/inet / {split($2, a, "/"); print a[1]}'` — PCRE lookbehind requires GNU grep with `-P`, which BusyBox grep doesn't support
- [2026-04-15] Replaced `mapfile -t IPS < <(...)` with `while IFS= read -r` loop + here-string — `mapfile` is bash 4+ only; here-string (`<<<`) works in bash 3+ which DSM 7 ships
- [2026-04-15] Added `ifconfig` fallback for IP detection — some DSM builds have limited `ip` command
- [2026-04-15] Fixed `insmod /lib/modules/tun.ko` → dynamic `find /lib/modules -name 'tun.ko*'` — DSM 7 stores kernel modules in versioned subdirectories, not at root
- [2026-04-15] Cleaned all `&>/dev/null 2>&1` → `>/dev/null 2>&1` — the `&>` bashism doubled stderr redirect redundantly

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
- `install.sh` has been patched for DSM 7+ compatibility (Task 5 in TODO.md). Changes need to be committed to a feature branch and PR'd.
- The `.github/` governance framework was copied from `crashcart/Kali-AI-term` on 2026-04-12.
- Rule scope has been updated to include `crashcart/zerotierone-moon`.

---

## 📁 Key File Reference

| File | Purpose |
|------|---------|
| `.github/copilot-instructions.md` | Enterprise agent rules |
| `.github/TODO.md` | Active + frozen task tracking |
| `.github/PLANNING.md` | This file |
| `.github/REPO_CONFIG.md` | Project-specific configuration |
