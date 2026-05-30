#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# get-latest-dev.sh — Install or update ZeroTier moon to latest dev branch
#
# Handles both cases automatically:
#   • Fresh Synology — clones repo and runs install.sh
#   • Existing install — pulls latest dev and runs update.sh --branch dev
#
# Prerequisites:
#   1. DSM Control Panel → Terminal & SNMP → Enable SSH service
#   2. DSM Package Center → Install "Git Server" (provides /usr/bin/git)
#   3. DSM Package Center → Install "Container Manager" (provides Docker)
#   4. SSH in: ssh admin@<NAS_IP>
#   5. Elevate: sudo -i
#   6. Run: curl -fsSL https://raw.githubusercontent.com/crashcart/zerotierone-moon/dev/get-latest-dev.sh | bash
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_URL="https://github.com/crashcart/zerotierone-moon.git"
REPO_BRANCH="dev"
REPO_DIR="/volume1/docker/zerotierone-moon"

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m' NC='\033[0m'
step() { echo -e "\n${B}[>]${NC} $*"; }
ok()   { echo -e "  ${G}✓${NC} $*"; }
warn() { echo -e "  ${Y}!${NC} $*"; }
die()  { echo -e "  ${R}✗${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo -i, then re-run"

command -v docker &>/dev/null \
    || die "Docker not found. Install Container Manager from DSM Package Center."

command -v git &>/dev/null \
    || die "git not found. Install 'Git Server' from DSM Package Center, then re-run."

ok "git $(git --version | awk '{print $3}')"
ok "docker $(docker --version | awk '{print $3}' | tr -d ',')"

# ── Existing git repo ────────────────────────────────────────────────────────
if [[ -d "$REPO_DIR/.git" ]]; then
    step "Existing repo found at $REPO_DIR"

    # Back up settings before any git operations — .env is gitignored so it is
    # never touched by checkout/pull, but a timestamped copy guarantees the
    # user's saved settings survive no matter what.
    if [[ -f "$REPO_DIR/.env" ]]; then
        mkdir -p "$REPO_DIR/.env-backups"
        cp "$REPO_DIR/.env" "$REPO_DIR/.env-backups/.env.$(date +%Y%m%d-%H%M%S)"
        ok "Settings backed up to $REPO_DIR/.env-backups/"
        # Keep the 10 most recent backups. Timestamped names sort oldest→newest
        # under a glob, so delete everything except the final 10.
        backups=("$REPO_DIR/.env-backups"/.env.*)
        if (( ${#backups[@]} > 10 )); then
            for ((bi = 0; bi < ${#backups[@]} - 10; bi++)); do
                rm -f "${backups[$bi]}"
            done
        fi
    fi

    # Pull latest dev first so update.sh itself is current
    git -C "$REPO_DIR" fetch origin "$REPO_BRANCH" --quiet \
        || warn "git fetch failed — proceeding with local copy"
    git -C "$REPO_DIR" checkout -- docker-compose.yml 2>/dev/null || true
    git -C "$REPO_DIR" checkout "$REPO_BRANCH" 2>/dev/null \
        || warn "Could not switch to $REPO_BRANCH"
    git -C "$REPO_DIR" pull origin "$REPO_BRANCH" \
        || warn "git pull failed — proceeding with local copy"
    ok "Repo updated to $REPO_BRANCH ($(git -C "$REPO_DIR" rev-parse --short HEAD))"

    if [[ ! -x /usr/local/bin/zmoon ]]; then
        warn "zmoon not in PATH — creating symlink"
        mkdir -p /usr/local/bin
        ln -sf "$REPO_DIR/zmoon" /usr/local/bin/zmoon
        ok "zmoon → /usr/local/bin/zmoon"
    fi

    # Decide update vs install by the real marker of a working install: the
    # ZeroTier identity. A present .env only means config was written — an
    # earlier install may have failed before the container ever started and
    # generated identity.secret. update.sh refuses to run without it, so only
    # take the update path when the identity actually exists.
    ZT_DATA_DIR="/volume1/docker/zerotier"
    if [[ -f "$REPO_DIR/.env" ]]; then
        _dd=$(grep -E '^DATA_DIR=' "$REPO_DIR/.env" | head -1 | cut -d= -f2- | tr -d '"')
        [[ -n "$_dd" ]] && ZT_DATA_DIR="$_dd"
    fi

    if [[ -f "$REPO_DIR/.env" && -f "$ZT_DATA_DIR/zerotier-one/identity.secret" ]]; then
        step "Running update.sh"
        bash "$REPO_DIR/update.sh"
    else
        warn "No working install yet (no identity) — running install.sh"
        bash "$REPO_DIR/install.sh"
    fi
    exit 0
fi

# ── Directory exists but is not a git repo — migrate ─────────────────────────
if [[ -d "$REPO_DIR" ]]; then
    warn "$REPO_DIR exists but is not a git repo — migrating old install"
    # Preserve .env so install.sh skips interactive prompts
    if [[ -f "$REPO_DIR/.env" ]]; then
        cp "$REPO_DIR/.env" /tmp/zerotier-env.bak
        ok ".env backed up to /tmp/zerotier-env.bak"
    fi
    mv "$REPO_DIR" "${REPO_DIR}.old"
    ok "Old directory moved to ${REPO_DIR}.old"
fi

# ── Fresh install ─────────────────────────────────────────────────────────────
step "Cloning $REPO_URL (branch: $REPO_BRANCH)"
mkdir -p "$(dirname "$REPO_DIR")"
git clone --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
ok "Cloned to $REPO_DIR"

# Restore .env from migration so install.sh runs non-interactively
if [[ -f /tmp/zerotier-env.bak ]]; then
    cp /tmp/zerotier-env.bak "$REPO_DIR/.env"
    rm /tmp/zerotier-env.bak
    ok ".env restored — install.sh will run non-interactively"
fi

ENV_FILE="$REPO_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    step "Setting up .env"
    cp "$REPO_DIR/.env.example" "$ENV_FILE"

    echo
    echo "  Fill in your network details. Press Enter to keep the shown default."
    echo "  Find your ZeroTier Network ID at: https://my.zerotier.com"
    echo

    _ask() {
        local prompt="$1" var="$2" current input tmp
        current=$(grep "^${var}=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' || echo "")
        read -rp "    ${prompt} [${current}]: " input
        input="${input:-$current}"
        tmp=$(mktemp)
        sed "s|^${var}=.*|${var}=${input}|" "$ENV_FILE" > "$tmp" && mv "$tmp" "$ENV_FILE"
        echo "      → ${var}=${input}"
    }

    _ask "ZeroTier Network ID (16 hex chars)"             ZT_NETWORK_ID
    _ask "LAN 1 subnet  (e.g. 192.168.1.0/24)"           LAN1_SUBNET
    _ask "LAN 1 gateway (e.g. 192.168.1.1)"              LAN1_GATEWAY
    _ask "LAN 1 container IP (e.g. 192.168.1.253)"       LAN1_CONTAINER_IP
    _ask "LAN 2 subnet  (e.g. 172.16.0.0/24)"            LAN2_SUBNET
    _ask "LAN 2 gateway (e.g. 172.16.0.1)"               LAN2_GATEWAY
    _ask "LAN 2 container IP (e.g. 172.16.0.253)"        LAN2_CONTAINER_IP
    _ask "Public static IP for moon endpoint (blank=skip, NO hostnames/DDNS)" ZT_PUBLIC_ENDPOINT

    ok ".env written"
fi

step "Running install.sh"
bash "$REPO_DIR/install.sh"
