# ZeroTier Moon — Ongoing Maintenance

## Status
active

## Goal
Keep the DS918+ ZeroTier moon node stack current, tested, and production-ready across all branches.

## Next Action
**2026-07-15 live install done + doctor triage (user deferred coding — "worry
about the code later").** NAS updated to dev via one-liner: moon ONLINE, direct
peer paths, policy routing OK, cron installed once, symlink bug found+fixed
live (zmoon now readlink-resolves itself; cron was silently dead before).
`zmoon boot` re-applied tuning → host conntrack 300s PASS.

**Root cause of remaining doctor FAIL/WARNs (diagnosed, fix deferred):** the
DS918+ DSM kernel lacks the iptables `raw` table (`unable to initialize table
'raw'`). iptables-restore is ATOMIC per file, so the whole rules.v4 aborts —
NOTRACK FAIL *and* missing zt+ FORWARD come from this one failure. fq WARN:
kernel likely lacks sch_fq too; entrypoint logs "Set fq qdisc" even when `tc
… || true` failed (misleading). rmem_max=0 WARN is a DOCTOR BUG: it reads
net.core.rmem_max inside the container (zmoon:356) where DSM blocks it — host
value is fine. Interim posture is safe: host conntrack 300s covers the
timeout NOTRACK guarded against; forwarding gap only affects LAN↔ZT gateway
traffic (unchanged from before — same kernel, newly surfaced by doctor).

**Deferred TODO (next coding session):**
1. entrypoint: on rules.v4 restore failure, retry with the *raw section
   stripped (filter/mangle/nat still apply → zt+ FORWARD restored); attempt
   host-side `modprobe iptable_raw sch_fq` from zmoon boot first.
2. fq: fall back to fq_codel when sch_fq is absent; stop logging success on
   failure.
3. doctor: read rmem_max on the HOST, not in the container ns.
4. update.sh: regenerate $DATA_DIR config files (rules.v4/v6, setuproutes,
   local.conf) so config drift between repo and data dir can't recur.
5. update.sh report: print 10-char world id (still prints padded filename).
6. **FEATURE (user request): TUN-connectivity watchdog interval — verify the
   connection hourly by default (60 min), editable from the web page.**
   Current watchdog piggybacks the 15-min tuning cron; make the verify
   cadence its own setting (WATCHDOG_INTERVAL_MIN=60 in .env, exposed as an
   editable field in the web console, cron line updated accordingly).

## Prior Next Action
**2026-07-06 install day:** `dev` fast-forwarded to `7249875` (user-approved) —
the documented one-liner now installs everything: web console + update API,
`zmoon boot/connect/install-cron/web`, tuning lib, perf fixes, and the
curl|bash prompt fix (prompts read /dev/tty; plain `read` was eating script
lines as input on fresh installs). CI green on dev. After the NAS install:
run `zmoon connect` for client commands, wire `zmoon boot` (Task Scheduler
Boot-up, root, absolute path) or `zmoon install-cron`, and do the live-QA pass
(`/api/status` against the running moon + one web-triggered update).

## Previous Next Action
**Web console initiative (in progress).** FRONTEND + BACKEND delivered a working beta:
`web/` — single-page console (Dashboard / Members / Connect) + `web/server.py`
(stdlib) serving live status and the auth-gated Update/Restart/authorize actions;
`zmoon web` launches it. The **Update button pulls the repo branch and runs the
installer, streaming the log live** (verified in a headless browser).
SECURITY INFRA review done (2026-07-05): 3 low findings fixed in `server.py`
(path-prefix confinement, JSON Content-Type gate blocking form CSRF, branch-name
validation); 2 findings accepted under the **trusted-LAN threat model** (user
directive) — unauthenticated `GET /api/status` and Basic Auth over plain HTTP.
`web/`-aware assertions added (61 tests total). Remaining before "gold": QA on
the live NAS — `/api/status` against a running moon (currently only the sample
fallback is exercised) and a real web-triggered update. Not internet-exposed.
On session start: run `bash tests/run.sh`, then proceed with user-directed work.

## Moon/client mode + fresh-install resilience — UI-tested (2026-07-06)
Delivered and pushed to dev (CI green, 97 tests). (1) entrypoint no longer
`die`s on fatal fresh-install states — it hold()s (alive+idle, unhealthy,
logs the fix) so `restart: always` can't crash-loop. (2) MOON_MODE in .env
(default true) → GENERATE_MOON in compose; client mode deorbits own moon but
keeps moon.json/moons.d (re-enable restores same Moon ID). (3) Web Dashboard
moon-mode checkbox: promote = confirm; demote = must TYPE the Moon ID, server
independently gates (428 on mismatch) — a stray click can't demote a live moon.
Field-passthrough audit: 43-assertion headless-browser suite proves every
status field reaches its DOM slot and the .env→compose→container-env chain
carries all fields. Bug caught by the test: web build_status emitted the
16-char padded moon id vs the 10-char world id the gate/CLI use — fixed.

## Stress test — SRE + TECH LEAD scrutiny (2026-07-05)
Joint slowdown/stability pass over the stack. Container config had no new
findings (prior tuning table stands). The web layer had one HIGH finding,
measured with a docker-shim stress harness (120ms/exec, 20 members):
`/api/status` spawned **24 docker execs / 3.1s per call** (one exec per member)
from an unauthenticated endpoint — ten viewers ≈ 240-exec stampede against
dockerd. Fixed by BACKEND DEVELOPER: bulk in-container jq walk (1 exec),
info+listpeers combined (1 exec), 3s single-flight TTL cache, cache
invalidation on writes, NETWORK_ID regex before shell interpolation, update-log
fd leak closed. After: **0.31s/2 execs cold; 0 execs warm; 2 execs for 10
cold-concurrent**. Security gates re-verified (401/415/404). 80 tests.

## Speed & Stability (user priority — 2026-07-05)
Audited the moon stack for throughput/latency and uptime/reboot-survival.
Container side already solid (restart:always, healthcheck, process-death detect,
fq qdisc, GARP, policy routing, NOTRACK, MSS clamp, socket buffers). **Gap found
and fixed:** host tuning (UDP buffers, conntrack 300s timeout, GRO/TSO/GSO
offload) did not survive a DSM reboot — DSM ignores `/etc/sysctl.conf` on boot
and offload resets. Added `lib/tuning.sh` (single source of truth) + `zmoon boot`
to re-apply it idempotently. **User action required:** add a DSM Task Scheduler
**Boot-up** task (user root) running `zmoon boot` — without it the moon returns
slower + prone to UDP cutouts after any reboot/DSM update.

## TODO — Tech Debt
- [x] **Removed temporary LAN2_GATEWAY hardcode** from `install.sh` (2026-05-30).
  No site-specific network values live in the code. On first install the gateway
  is auto-detected; if a NIC's gateway is not auto-detectable it stays blank
  (macvlan omits `--gateway`, which is cosmetic) and the user can set it in `.env`.
  Existing `.env` is authoritative and preserved across reinstalls.
- [ ] **Optional future improvement**: per-NIC gateway detection for the second
  NIC (DSM exposes only one system default route, via eth0), or an optional
  prompt when detection returns blank — without storing any value in the repo.

## Context
- Branch: `dev` — all work targets dev; promotions to alpha/beta/main require explicit human instruction
- Test suite: `bash tests/run.sh` → 55 checks (syntax, shellcheck, config, zmoon CLI, installer guards)
- `docker-compose.yml` is gitignored — generated by `generate_compose()` in `lib/compose.sh`
- `zmoon update` always regenerates compose before restart; `zmoon autoupdate` for daily cron
- AI-rules: v1.34.0 synced 2026-07-05; SHA ddf496ac94ef1e1efd24975435648392fae64b350ba9a824bdb8fb18a9fd788c (rules/*.md unchanged since v1.29.5 — governance/tooling additions only)
- `.ai-rules/` gitignored; sync via `/update-rules` slash command (pre-authorized, no prompt)
- `/update-rules` uses `curl | bash` — do NOT run `bash .ai-rules/scripts/sync-rules.sh` directly (self-detection bug)
- PM profile v1.29.4: Session Activation Protocol step 1 = roster check (agents/registry.json)
- RULE 23 compliance: this file satisfies plan persistence requirement

## Completed This Sprint (2026-05-26)
- Auto-update feature + lib/compose.sh + branch-switch conflict fix (PR #29)
- Gold-build audit — 7 defects fixed including CI compose generation (PR #30)
- Research audit — DDNS hostname bug fixed; buffer size corrected; governance docs updated
- AI-rules v1.28.1 loaded; RULE 23 compliance established (this file)
- AI-rules v1.28.2 sync complete — .ai-rules/ bootstrapped via sync-rules.sh; gitignored

## Completed This Sprint (2026-05-29)
- `get-latest-dev.sh` added — one-line Synology install/update bootstrap
- AI-rules synced to v1.29.5; ack.json current, SHA verified, no conflicts
  - v1.29.0: PM profile rewrite (Session Activation Protocol, Rule Enforcement Authority)
  - v1.29.3: /update-rules slash command added + allowedTools pre-approval
  - v1.29.4: PM Session Activation Protocol step 1 = roster check
  - v1.29.5: .claude/commands/ now synced to repo root
  - Patched /update-rules to use curl | bash (upstream uses local path which hits self-detection bug)
