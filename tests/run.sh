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

SHELL_SCRIPTS=(install.sh update.sh entrypoint.sh zmoon config/setuproutes.sh tests/run.sh)

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

assert_grep "rules.v4 has NOTRACK"          'NOTRACK'                  cat config/rules.v4
assert_grep "rules.v4 has *raw table"       '^\*raw'                   cat config/rules.v4
assert_grep "rules.v4 has *mangle mark"     'FORWARD -i zt\+ -j MARK'  cat config/rules.v4
assert_grep "rules.v4 has FORWARD accept"   'FORWARD.*zt\+.*ACCEPT'    cat config/rules.v4
assert_grep "MASQUERADE scoped by mark"     'POSTROUTING -m mark'      cat config/rules.v4
# Regression: -i is ILLEGAL in nat/POSTROUTING and aborts the whole restore
if grep -qE 'POSTROUTING -i ' config/rules.v4; then
    no "rules.v4 must NOT use -i in POSTROUTING (aborts iptables-restore)"
else
    ok "rules.v4 has no illegal -i in POSTROUTING"
fi
assert_grep "rt_tables defines ISP_1"       'ISP_1'                    cat config/rt_tables
assert_grep "rt_tables defines ISP_2"       'ISP_2'                    cat config/rt_tables

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
assert_grep "update.sh prunes old backups" \
    'Pruned old backups' cat update.sh
assert_grep "entrypoint detects ZeroTier process death" \
    'kill -0' cat entrypoint.sh

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
