# TODO

## Review Items

- [x] **IPv6 ip6tables + TCP MSS clamping** — complete (2026-05-20)
  - Add `TCPMSS --clamp-mss-to-pmtu` to mangle table in `config/rules.v4` and `install.sh` generated copy
  - Create `config/rules.v6` with IPv6 FORWARD + ICMPv6 + *mangle MSS clamping (no NAT for IPv6)
  - Apply `ip6tables-restore` in `entrypoint.sh` if `rules.v6` exists
  - Add tests to `tests/run.sh` for MSS clamping and IPv6 rules (49 total)
  - PRs #17 + #18 merged to dev

- [x] **Implement ZeroTier on DS918+ (dual NIC)** — complete
  - Custom `zerotier-moon` image (Alpine 3.21, built locally via `Dockerfile`)
  - Dual macvlan networks (macvlan-lan1 / macvlan-lan2) with policy routing
  - Moon generation, identity persistence, and update tooling complete
  - Stability improvements: NET_RAW, NOTRACK, conntrack timeout, healthcheck, 8 MB UDP buffers (2× BDP for J3455), fq qdisc, local.conf port pinning

- [x] **Polish into a cohesive product** — complete
  - Unified `zmoon` CLI: install / update / status / doctor / peers / moon-id / backup / restore / logs / version / autoupdate
  - `zmoon doctor` — automated PASS/WARN/FAIL diagnostics with non-zero exit (cron-friendly)
  - Dependency-free test suite (`tests/run.sh`) wired into CI; all shell scripts ShellCheck-clean
  - **Critical fix**: removed illegal `-i` in nat/POSTROUTING that aborted the entire
    iptables ruleset on every DSM host (NOTRACK/FORWARD/MASQUERADE were never applying)
  - Audit fixes: `ip rule` flush loop, `.env` gitignored, entrypoint process-death
    detection, bounded backups, macvlan `--ip-range`, network-ID validation

- [x] **Auto-update + old-install migration** — complete (2026-05-26, PR #29)
  - `lib/compose.sh` — shared `generate_compose()` sourced by both install.sh and update.sh
  - `docker-compose.yml` gitignored; regenerated on every `zmoon update` (fixes branch-switch conflict on initialized installs)
  - `zmoon autoupdate` — check remote, skip if disabled/current, run update + log to `$DATA_DIR/autoupdate.log`
  - `AUTO_UPDATE` / `AUTO_UPDATE_BRANCH` in `.env` and `.env.example`
  - 53 tests

- [x] **Gold-build audit** — complete (2026-05-26, PR #30)
  - CI: `build.yml` / `test.yml` now generate `docker-compose.yml` from `lib/compose.sh` before validation (file was gitignored — CI was failing on every push)
  - `update.sh`: `generate_compose` unconditional (not only on `--branch`); fixes fresh-clone crash
  - `zmoon help` range fixed (`sed 3,19p`); `lib/compose.sh` added to shellcheck + tests
  - README: Step 5 replaced stale 3rd-party compose snippet; rules.v4 snippet updated; Updating section rewritten
  - 55 tests

- [x] **Research audit + DDNS bug fix** — complete (2026-05-26)
  - ZT `stableEndpoints` requires bare IP addresses — DDNS hostnames are silently ignored
  - Fixed `.env.example`, `install.sh` prompt, `README.md` Step 7, and `RESEARCH.md`
  - Corrected RESEARCH.md buffer size (said 25 MB, was changed to 8 MB)
  - PLANNING.md + TODO.md brought current

---

## Remaining / Out of Scope

- [ ] Port forward UDP 9993 on router if serving external clients (user responsibility)
- [ ] Add ZeroNSD as second compose service (out of scope for this deployment)
- [ ] Add managed routes instructions to README (optional enhancement)
