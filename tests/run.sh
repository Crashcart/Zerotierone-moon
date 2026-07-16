#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Test suite for the ZeroTier moon toolkit.
#
# Pure bash (no bats dependency). Covers:
#   - shell syntax (bash -n) for every script
#   - shellcheck (if available)
#   - config file validity (local.conf JSON, rules.v4 structure, rt_tables)
#   - zmoon offline behaviour (help/version/unknown-command/dispatch)
#
# Usage:  bash tests/run.sh
# Exit:   0 = all passed, 1 = one or more failures
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || { echo "cannot cd to repo root: $ROOT" >&2; exit 1; }

PASS=0 FAIL=0
if [[ -t 1 ]]; then G='\033[0;32m' R='\033[0;31m' DIM='\033[2m' NC='\033[0m'
else G='' R='' DIM='' NC=''; fi

ok()   { echo -e "  ${G}ok${NC}   $*"; PASS=$(( PASS + 1 )); }
no()   { echo -e "  ${R}FAIL${NC} $*"; FAIL=$(( FAIL + 1 )); }
group(){ echo -e "\n${DIM}== $* ==${NC}"; }

# assert_ok "desc" cmd...        — passes if cmd exits 0
assert_ok() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else no "$desc"; fi
}
# assert_exit CODE "desc" cmd... — passes if cmd exits with CODE
assert_exit() {
    local want="$1" desc="$2"; shift 2
    "$@" >/dev/null 2>&1
    local got=$?
    if [[ "$got" -eq "$want" ]]; then ok "$desc"; else no "$desc (want exit $want, got $got)"; fi
}
# assert_grep "desc" PATTERN cmd... — passes if cmd output matches PATTERN
assert_grep() {
    local desc="$1" pat="$2"; shift 2
    if "$@" 2>/dev/null | grep -qE "$pat"; then ok "$desc"; else no "$desc"; fi
}

SHELL_SCRIPTS=(install.sh update.sh entrypoint.sh get-latest-dev.sh zmoon lib/compose.sh lib/tuning.sh config/setuproutes.sh tests/run.sh)

# ─── 1. Shell syntax ─────────────────────────────────────────────────────────
group "shell syntax (bash -n)"
for f in "${SHELL_SCRIPTS[@]}"; do
    if [[ -f "$f" ]]; then
        assert_ok "syntax: $f" bash -n "$f"
    else
        no "missing: $f"
    fi
done

# ─── 2. shellcheck (optional) ────────────────────────────────────────────────
group "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
    for f in "${SHELL_SCRIPTS[@]}"; do
        [[ -f "$f" ]] && assert_ok "shellcheck: $f" shellcheck -S warning "$f"
    done
else
    echo -e "  ${DIM}skip${NC} shellcheck not installed"
fi

# ─── 3. Config files ─────────────────────────────────────────────────────────
group "config files"
if command -v jq >/dev/null 2>&1; then
    assert_ok "local.conf is valid JSON" jq -e . config/local.conf
    assert_grep "local.conf pins primaryPort 9993" '"primaryPort": *9993' \
        cat config/local.conf
    assert_grep "local.conf blacklists docker/zt ifaces" '(docker|zt)' \
        jq -r '.settings.interfacePrefixBlacklist[]' config/local.conf
else
    no "jq not available — cannot validate local.conf"
fi

assert_grep "rules.v4 has NOTRACK"           'NOTRACK'                        cat config/rules.v4
assert_grep "rules.v4 has *raw table"        '^\*raw'                         cat config/rules.v4
assert_grep "rules.v4 has *mangle mark"      'FORWARD -i zt\+ -j MARK'        cat config/rules.v4
assert_grep "rules.v4 has MSS clamping"      'TCPMSS.*clamp-mss-to-pmtu'      cat config/rules.v4
assert_grep "rules.v4 has FORWARD accept"    'FORWARD.*zt\+.*ACCEPT'          cat config/rules.v4
assert_grep "MASQUERADE scoped by mark"      'POSTROUTING -m mark'            cat config/rules.v4
# Regression: -i is ILLEGAL in nat/POSTROUTING and aborts the whole restore
if grep -qE 'POSTROUTING -i ' config/rules.v4; then
    no "rules.v4 must NOT use -i in POSTROUTING (aborts iptables-restore)"
else
    ok "rules.v4 has no illegal -i in POSTROUTING"
fi
assert_grep "rt_tables defines ISP_1"        'ISP_1'                          cat config/rt_tables
assert_grep "rt_tables defines ISP_2"        'ISP_2'                          cat config/rt_tables

# iptables-restore --test needs CAP_NET_ADMIN. Run it directly if we're root,
# via passwordless sudo if available, otherwise skip (the static -i regression
# check above still guards the specific bug this caught).
if command -v iptables-restore >/dev/null 2>&1; then
    if [[ "$(id -u)" -eq 0 ]]; then
        assert_ok "rules.v4 passes iptables-restore --test" \
            sh -c 'iptables-restore --test < config/rules.v4'
    elif sudo -n true 2>/dev/null; then
        assert_ok "rules.v4 passes iptables-restore --test (sudo)" \
            sh -c 'sudo iptables-restore --test < config/rules.v4'
    else
        echo -e "  ${DIM}skip${NC} iptables-restore needs privileges (not root, no sudo)"
    fi
else
    echo -e "  ${DIM}skip${NC} iptables-restore not available"
fi

assert_grep "rules.v6 has *mangle MSS clamp"  'TCPMSS.*clamp-mss-to-pmtu'      cat config/rules.v6
assert_grep "rules.v6 has FORWARD accept"    'FORWARD.*zt\+.*ACCEPT'          cat config/rules.v6
assert_grep "rules.v6 allows ICMPv6"         'FORWARD -p icmpv6'              cat config/rules.v6
# IPv6 must NOT have a *nat table — NAT is not used with IPv6 global addresses
if grep -q '^\*nat' config/rules.v6 2>/dev/null; then
    no "rules.v6 must NOT have a *nat table"
else
    ok "rules.v6 has no *nat table (correct for IPv6)"
fi

if command -v ip6tables-restore >/dev/null 2>&1; then
    if [[ "$(id -u)" -eq 0 ]]; then
        assert_ok "rules.v6 passes ip6tables-restore --test" \
            sh -c 'ip6tables-restore --test < config/rules.v6'
    elif sudo -n true 2>/dev/null; then
        assert_ok "rules.v6 passes ip6tables-restore --test (sudo)" \
            sh -c 'sudo ip6tables-restore --test < config/rules.v6'
    else
        echo -e "  ${DIM}skip${NC} ip6tables-restore needs privileges (not root, no sudo)"
    fi
else
    echo -e "  ${DIM}skip${NC} ip6tables-restore not available"
fi

# ─── 4. setuproutes.sh correctness ───────────────────────────────────────────
group "setuproutes.sh"
assert_grep "flush loop deletes ALL rules (not single del)" \
    'while ip rule del table' cat config/setuproutes.sh
assert_grep "has container-IP priority rules"  'priority 9[89]' cat config/setuproutes.sh
assert_grep "has main-table fallback default"  'default via .* metric 200' \
    cat config/setuproutes.sh

# ─── 5. zmoon offline behaviour ──────────────────────────────────────────────
group "zmoon CLI (offline)"
assert_ok      "zmoon help exits 0"                 ./zmoon help
assert_grep    "zmoon help lists 'doctor'"  'zmoon doctor'  ./zmoon help
assert_grep    "zmoon help lists 'backup'"  'zmoon backup'  ./zmoon help
assert_ok      "zmoon version exits 0"              ./zmoon version
assert_grep    "zmoon version prints version" 'zmoon v[0-9]' ./zmoon version
assert_exit 64 "unknown command exits 64"           ./zmoon definitely-not-a-command
assert_ok      "zmoon (no args) defaults to help"   ./zmoon

# ─── 6. install.sh / update.sh guards ────────────────────────────────────────
group "installer guards"
assert_grep "install.sh validates ZT_NETWORK_ID format" \
    '16 hex characters' cat install.sh
assert_grep "install.sh scopes macvlan with --ip-range" \
    '\-\-ip-range' cat install.sh
assert_grep "install.sh generates mark-based MASQUERADE" \
    'POSTROUTING -m mark' cat install.sh
assert_grep "install.sh generates MSS clamping rule" \
    'TCPMSS.*clamp-mss-to-pmtu' cat install.sh
assert_grep "install.sh generates rules.v6" \
    'rules\.v6' cat install.sh
assert_grep "install.sh generates IPv6 MSS clamping" \
    'TCPMSS.*clamp-mss-to-pmtu' cat install.sh
assert_grep "entrypoint applies ip6tables rules" \
    'ip6tables-restore' cat entrypoint.sh
assert_grep "update.sh prunes old backups" \
    'Pruned old backups' cat update.sh
assert_grep "entrypoint detects ZeroTier process death" \
    'kill -0' cat entrypoint.sh
assert_grep "zmoon help lists 'autoupdate'"              'autoupdate'           ./zmoon help
assert_grep ".env.example has AUTO_UPDATE"               'AUTO_UPDATE'          cat .env.example
assert_grep ".env.example has AUTO_UPDATE_BRANCH"        'AUTO_UPDATE_BRANCH'   cat .env.example
assert_grep "update.sh regenerates compose after pull"   'generate_compose'     cat update.sh

# ─── Web console ─────────────────────────────────────────────────────────────
group "web console"
assert_ok   "web/server.py has valid python syntax"      python3 -m py_compile web/server.py
assert_ok   "web/status.sample.json is valid JSON"       jq -e . web/status.sample.json
assert_grep "zmoon help lists 'web'"                     'zmoon web'            ./zmoon help
assert_grep "server.py gates actions behind auth"        'WEB_ADMIN_PASSWORD'  cat web/server.py
assert_grep "server.py validates branch names"           'BRANCH_RE'           cat web/server.py
assert_grep ".env.example documents WEB_ADMIN_PASSWORD"  'WEB_ADMIN_PASSWORD'  cat .env.example

# ─── Boot re-apply (reboot survival of host tuning) ──────────────────────────
group "boot / host tuning"
assert_grep "zmoon help lists 'boot'"                    'zmoon boot'          ./zmoon help
assert_grep "lib/tuning.sh defines HOST_SYSCTLS"         'HOST_SYSCTLS='       cat lib/tuning.sh
assert_grep "tuning centralizes conntrack UDP timeout"   'nf_conntrack_udp_timeout=300' cat lib/tuning.sh
assert_grep "install.sh sources shared tuning"           'source .*lib/tuning.sh'       cat install.sh
assert_grep "install.sh has no inline sysctl value dup"  'HOST_SYSCTLS'        cat install.sh
# shellcheck disable=SC2016  # expansion is intentional inside the bash -c subshell
assert_ok   "lib/tuning.sh sources without error"        bash -c 'source lib/tuning.sh && [ ${#HOST_SYSCTLS[@]} -ge 5 ]'
assert_grep "zmoon help lists 'connect'"                 'zmoon connect'       ./zmoon help
assert_grep "zmoon help lists 'install-cron'"            'zmoon install-cron'  ./zmoon help
assert_grep "zmoon derives 10-char world id (not padded)" 'moon_world_id'      cat zmoon
assert_grep "connect uses moon_world_id for orbit"       'moon_world_id'       cat zmoon
assert_grep "install-cron targets /etc/crontab"          '/etc/crontab'        cat zmoon
assert_grep "zmoon hardens PATH for DSM cron (minimal env)" 'export PATH=.*local/bin' cat zmoon
assert_grep "cron reload tries DSM-native synosystemctl"  'synosystemctl'       cat zmoon

# ─── Web perf (stress-test regression guards, 2026-07-05) ────────────────────
# One docker exec per member cost 24 execs / 3.1s per status call; the bulk
# fetch + single-flight cache brought it to 2 execs / 0.3s. Guard the shape.
assert_grep "status uses bulk controller fetch (no N+1)"  'controller_network_and_members' cat web/server.py
assert_grep "info+peers combined into one docker exec"    'zt_info_and_peers'   cat web/server.py
assert_grep "status responses served from TTL cache"      'STATUS_TTL'          cat web/server.py
assert_grep "network id validated before shell interpolation" 'NETWORK_ID_RE'   cat web/server.py

# ─── curl|bash install path (one-line install regression guards) ─────────────
# Under `curl | sudo bash` stdin is the exhausted pipe: a plain `read` hits EOF
# and set -e kills the install at the first prompt. Prompts must use /dev/tty.
assert_grep "install.sh prompts read the terminal, not stdin"  '/dev/tty'      cat install.sh
assert_grep "get-latest-dev.sh prompts read the terminal"      '/dev/tty'      cat get-latest-dev.sh
assert_grep "install.sh ask() dies clean when non-interactive" 'no terminal'   cat install.sh

# ─── Moon/client mode + crash-loop resilience ────────────────────────────────
group "moon mode + resilience"
assert_grep "entrypoint holds (no restart loop) on fatal"      'while :; do sleep' cat entrypoint.sh
assert_grep "fatal paths use hold, not exit"                   'hold "ZeroTier'    cat entrypoint.sh
assert_grep "client mode deorbits own moon, keeps files"       'CLIENT MODE'       cat entrypoint.sh
assert_grep "compose gates moon on MOON_MODE"                  'GENERATE_MOON=..MOON_MODE' cat lib/compose.sh
assert_grep ".env.example documents MOON_MODE"                 'MOON_MODE=true'    cat .env.example
assert_grep "install.sh writes MOON_MODE to .env"             'MOON_MODE=true'    cat install.sh
assert_grep "server exposes moonMode in status"               'moonMode'          cat web/server.py
assert_grep "demote requires typed confirm (428 gate)"        'confirmation mismatch' cat web/server.py
assert_grep "demote confirm compares the moon world id"       'moon_world_id'     cat web/server.py
assert_grep "status moon.id is the 10-char world id"          'moon_id = moon_world_id' cat web/server.py
assert_grep "UI has the guarded moon-mode toggle"             'moon-toggle'       cat web/index.html
assert_grep "UI toggle demote uses a typed prompt"            'Type .{0,40}Moon ID' cat web/app.js

# ─── Data-plane speed (RPS multi-core packet steering) ───────────────────────
group "data-plane speed"
assert_grep "tuning defines enable_rps"                       'enable_rps\(\)'   cat lib/tuning.sh
assert_grep "host tuning applies RPS to both NICs"            'enable_rps ..if[12]' cat lib/tuning.sh
assert_grep "host sysctls include RFS flow entries"           'rps_sock_flow_entries' cat lib/tuning.sh
assert_grep "host sysctls include udp_rmem_min"               'udp_rmem_min'     cat lib/tuning.sh
assert_grep "entrypoint spreads RPS in container netns"       'rps_cpus'         cat entrypoint.sh
assert_grep "rules.v4 NOTRACK covers both directions"         'OUTPUT -p udp --sport 9993 -j NOTRACK' cat config/rules.v4
assert_grep "boot watchdog restarts offline moon"             'WATCHDOG'         cat zmoon
assert_grep "watchdog skips held (unconfigured) containers"   'held for inspection' cat zmoon
assert_grep "install.sh auto-installs the tuning cron"        'zmoon.{0,3} install-cron' cat install.sh
assert_grep "update.sh ensures the tuning cron too"           'zmoon.{0,3} install-cron' cat update.sh

# Live idempotency: 3 installs against a fake crontab must yield exactly 1 job.
# ZMOON_CRONTAB points install-cron at a temp file, so the real /etc/crontab
# is never touched. Root-only (the command refuses otherwise); CI skips.
if [[ "$(id -u)" -eq 0 ]]; then
    _fc=$(mktemp); printf '# fake crontab\n' > "$_fc"
    for _ in 1 2 3; do ZMOON_CRONTAB="$_fc" ./zmoon install-cron >/dev/null 2>&1 || true; done
    _n=$(grep -c 'zmoon boot' "$_fc" 2>/dev/null || true)   # grep -c prints 0 itself on no-match
    if [[ "$_n" -eq 1 ]]; then ok "install-cron idempotent (3 runs → 1 job)"; else no "install-cron idempotent (3 runs → $_n jobs)"; fi
    ZMOON_CRONTAB="$_fc" ./zmoon uninstall-cron >/dev/null 2>&1 || true
    _n=$(grep -c 'zmoon boot' "$_fc" 2>/dev/null || true)   # grep -c prints 0 itself on no-match
    if [[ "$_n" -eq 0 ]]; then ok "uninstall-cron removes the job"; else no "uninstall-cron removes the job ($_n left)"; fi
    rm -f "$_fc"
else
    ok "install-cron idempotency (skipped — needs root)"
fi

# zmoon must work when invoked via a symlink (that's how /usr/local/bin and the
# cron call it). Regression for: SCRIPT_DIR resolved to the symlink's dir, so
# .env/lib were never found and `zmoon boot` from cron died on every firing.
assert_grep "zmoon resolves its own symlink"                  'readlink -f'      cat zmoon
_ld=$(mktemp -d); ln -s "$ROOT/zmoon" "$_ld/zmoon"
assert_grep "zmoon help works via symlink"                    'zmoon boot'       "$_ld/zmoon" help
rm -rf "$_ld"

# ─── DSM raw-table resilience (live-NAS doctor triage, 2026-07-15) ──────────
group "raw-table resilience"
assert_grep "entrypoint retries restore without raw table"    'retrying without the raw table' cat entrypoint.sh
assert_grep "entrypoint falls back to fq_codel"               'fq_codel'         cat entrypoint.sh
assert_grep "entrypoint falls back to sfq (DSM kernel has it)" 'root sfq perturb' cat entrypoint.sh
assert_grep "doctor accepts sfq qdisc as PASS"                'sfq).*chk_pass'   cat zmoon
assert_grep "first iptables attempt stderr suppressed"        'rules.v4 2>/dev/null' cat entrypoint.sh
assert_grep "RPS writes wrapped to hide read-only-FS errors"  'RPS_MASK" > "\$q/rps_cpus" \) +2>/dev/null' cat entrypoint.sh
assert_exit 1 "no em-dash in entrypoint log/hold output"      sh -c 'grep -nE "(log|hold) \"" entrypoint.sh | grep -q "—"'
assert_grep "entrypoint no longer logs fq success blindly"    'could not set fq' cat entrypoint.sh
assert_grep "tuning tries to load iptable_raw + sch_fq"       'iptable_raw'      cat lib/tuning.sh
assert_grep "doctor reads rmem_max on the host"               'host rmem_max'    cat zmoon
assert_grep "doctor downgrades NOTRACK when raw impossible"   'raw table unavailable' cat zmoon
assert_grep "update report prints 10-char world id"           'MOON_ID: -10'     cat update.sh
# The strip must remove the raw section entirely while keeping every other
# table — a botched strip would silently drop FORWARD/MSS/masquerade again.
_sv=$(mktemp)
awk '/^\*raw$/{skip=1} !skip{print} skip&&/^COMMIT$/{skip=0}' config/rules.v4 > "$_sv"
assert_exit 1 "stripped set has no raw section"    grep -q '^\*raw' "$_sv"
assert_ok      "stripped set keeps filter table"   grep -q '^\*filter' "$_sv"
assert_ok      "stripped set keeps mangle table"   grep -q '^\*mangle' "$_sv"
assert_ok      "stripped set keeps nat table"      grep -q '^\*nat' "$_sv"
assert_ok      "stripped set keeps zt+ FORWARD"    grep -q 'FORWARD.*zt' "$_sv"
rm -f "$_sv"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo
echo -e "${DIM}─────────────────────────────────────────────${NC}"
if [[ "$FAIL" -eq 0 ]]; then
    echo -e "${G}All $PASS checks passed.${NC}"
    exit 0
else
    echo -e "${R}$FAIL failed${NC}, $PASS passed."
    exit 1
fi
