# 🗺️ Zerotierone-moon Planning & Coordination

> 🔒 **GOVERNANCE FILE** — Protected by Rule 10 in `copilot-instructions.md`. Follow full workflow when editing.

**Last Updated**: 2026-04-12
**Document Purpose**: Centralized planning for multi-agent coordination, architectural decisions, and project context

---

## 🎯 Active Initiatives

### Initial Project Setup — Moon Node for Synology DSM 7+

**Status**: ✅ Complete — PR ready for review
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
- This repo is a new skeleton. Start by reading `REPO_CONFIG.md` and the open issues.
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
