#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# ZeroTier Moon Updater — Synology DS918+
# Rebuilds the Docker image and restarts the container WITHOUT touching the
# moon identity, moons.d/, or network config. Safe to run at any time.
#
# Usage:
#   bash update.sh                        — rebuild image, recreate macvlan nets if
#                                           missing, restart container
#   bash update.sh --branch <name>        — switch repo to <name> branch first,
#                                           then rebuild and restart
#   bash update.sh --no-build             — skip rebuild, just recreate nets + restart
#   bash update.sh --status               — show current status only, no changes
#
# Branch examples:
#   bash update.sh --branch main          — upgrade to stable release
#   bash update.sh --branch beta          — upgrade to beta
#   bash update.sh --branch dev           — upgrade to dev/bleeding-edge
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
# shellcheck source=lib/compose.sh
source "$SCRIPT_DIR/lib/compose.sh"

# ─── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m' NC='\033[0m'
step() { echo -e "\n${B}[>]${NC} $*"; }
ok()   { echo -e "  ${G}✓${NC} $*"; }
warn() { echo -e "  ${Y}!${NC} $*"; }
die()  { echo -e "  ${R}✗${NC} $*" >&2; exit 1; }

# Print the Moon ID (filename without .moon) of the first moon file, if any.
# Uses a bash glob (not ls) so filenames with odd characters are safe.
moon_id_of() {
    local dir="$1" f
    shopt -s nullglob
    for f in "$dir"/*.moon; do
        basename "$f" .moon
        shopt -u nullglob
        return 0
    done
    shopt -u nullglob
    return 1
}

# Count .moon files in a directory via a glob.
moon_count_of() {
    local dir="$1" files
    shopt -s nullglob
    files=("$dir"/*.moon)
    shopt -u nullglob
    echo "${#files[@]}"
}

[[ $EUID -eq 0 ]] || die "Run as root: sudo -i, then bash update.sh"
command -v docker &>/dev/null || die "Docker not found."

# Detect docker compose v2 plugin vs docker-compose v1 binary (DSM 7.0/7.1)
if docker compose version &>/dev/null 2>&1; then
    dc() { docker compose "$@"; }
elif command -v docker-compose &>/dev/null 2>&1; then
    dc() { docker-compose "$@"; }
else
    die "Neither 'docker compose' nor 'docker-compose' found — install Docker Compose"
fi

# ─── Parse args ───────────────────────────────────────────────────────────────
DO_BUILD=true
STATUS_ONLY=false
UPGRADE_BRANCH=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
        --no-build)  DO_BUILD=false ;;
        --status)    STATUS_ONLY=true ;;
        --branch)
            i=$(( i + 1 ))
            UPGRADE_BRANCH="${args[$i]:-}"
            [[ -z "$UPGRADE_BRANCH" ]] && die "--branch requires a branch name"
            ;;
        --branch=*)  UPGRADE_BRANCH="${args[$i]#--branch=}" ;;
    esac
    i=$(( i + 1 ))
done

# ─── Load config ──────────────────────────────────────────────────────────────
[[ -f "$ENV_FILE" ]] || die ".env not found — run install.sh first"
# shellcheck source=/dev/null
source "$ENV_FILE"

DATA_DIR="${DATA_DIR:-/volume1/docker/zerotier}"
CONTAINER_NAME="${CONTAINER_NAME:-zerotier-moon}"
IMAGE_NAME="${IMAGE_NAME:-zerotier-moon}"

# Validate all required networking variables are present. Gateways are
# intentionally NOT required — a same-L2 second NIC may legitimately have none,
# and macvlan creation below omits --gateway when blank (matches install.sh).
_required=(LAN1_SUBNET LAN1_CONTAINER_IP LAN2_SUBNET LAN2_CONTAINER_IP)
for _v in "${_required[@]}"; do
    [[ -n "${!_v:-}" ]] || die ".env is missing required variable: $_v — re-run install.sh"
done
unset _required _v

# Sanitize gateway values — a stale .env may hold an interface name instead of
# an IP (older buggy detection). If it is not a valid IPv4, blank it so macvlan
# omits --gateway rather than passing a value Docker rejects.
_is_ipv4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
for _gw in LAN1_GATEWAY LAN2_GATEWAY; do
    if [[ -n "${!_gw:-}" ]] && ! _is_ipv4 "${!_gw}"; then
        warn "$_gw='${!_gw}' is not a valid IP — ignoring (macvlan will omit --gateway)"
        printf -v "$_gw" '%s' ""
    fi
done
unset _gw

# ─── Status only ──────────────────────────────────────────────────────────────
if $STATUS_ONLY; then
    echo -e "\n${B}ZeroTier Moon Status${NC}"
    echo "  Container : $(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo 'not found')"
    echo "  ZT Status : $(docker exec "$CONTAINER_NAME" zerotier-cli status 2>/dev/null || echo 'unreachable')"
    echo "  Moon ID   : $(moon_id_of "$DATA_DIR/zerotier-one/moons.d" || echo 'none')"
    echo "  Peers     :"
    docker exec "$CONTAINER_NAME" zerotier-cli listpeers 2>/dev/null || echo "    (unavailable)"
    exit 0
fi

# ─── Upgrade to target branch ─────────────────────────────────────────────────
if [[ -n "$UPGRADE_BRANCH" ]]; then
    step "Switching repo to branch: $UPGRADE_BRANCH"
    command -v git &>/dev/null || die "git not found — cannot switch branches"
    git -C "$SCRIPT_DIR" fetch origin || die "git fetch failed"
    # docker-compose.yml is a generated artefact — discard it so checkout never conflicts
    git -C "$SCRIPT_DIR" checkout -- docker-compose.yml 2>/dev/null || true
    CURRENT_BRANCH=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD)
    if [[ "$CURRENT_BRANCH" != "$UPGRADE_BRANCH" ]]; then
        git -C "$SCRIPT_DIR" checkout "$UPGRADE_BRANCH" || die "git checkout $UPGRADE_BRANCH failed"
    fi
    git -C "$SCRIPT_DIR" pull origin "$UPGRADE_BRANCH" || die "git pull failed"
    ok "Repo updated to branch $UPGRADE_BRANCH ($(git -C "$SCRIPT_DIR" rev-parse --short HEAD))"
fi

# ─── Guard: verify moon identity is intact ────────────────────────────────────
step "Checking moon identity"

IDENTITY_SECRET="$DATA_DIR/zerotier-one/identity.secret"
IDENTITY_PUBLIC="$DATA_DIR/zerotier-one/identity.public"
MOONS_DIR="$DATA_DIR/zerotier-one/moons.d"

[[ -f "$IDENTITY_SECRET" ]] || die "identity.secret missing at $IDENTITY_SECRET — moon identity lost. Re-run install.sh to start fresh."
[[ -f "$IDENTITY_PUBLIC" ]] || die "identity.public missing at $IDENTITY_PUBLIC"

MOON_FILES=$(moon_count_of "$MOONS_DIR")
if [[ "$MOON_FILES" -eq 0 ]]; then
    warn "No .moon files found in $MOONS_DIR — moon will be recompiled on next start (identity preserved)"
else
    MOON_ID=$(moon_id_of "$MOONS_DIR")
    ok "Moon identity intact — ID: $MOON_ID"
fi

# ─── Backup moon identity ──────────────────────────────────────────────────────
step "Backing up moon identity"

BACKUP_DIR="$DATA_DIR/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$IDENTITY_SECRET" "$BACKUP_DIR/"
cp "$IDENTITY_PUBLIC" "$BACKUP_DIR/"
[[ -f "$DATA_DIR/zerotier-one/moon.json" ]] && cp "$DATA_DIR/zerotier-one/moon.json" "$BACKUP_DIR/"
ok "Identity backed up to $BACKUP_DIR"

# Prune old backups — keep the 5 most recent to avoid unbounded disk growth.
# bash expands globs in lexical order, and backup names are timestamped
# (YYYYMMDD-HHMMSS), so the array is already oldest→newest. No mapfile/sort
# (kept bash 3 compatible — update.sh runs on the DSM host).
shopt -s nullglob
BACKUPS=("$DATA_DIR"/backups/[0-9]*/)
shopt -u nullglob
if [[ "${#BACKUPS[@]}" -gt 5 ]]; then
    for ((i = 0; i < ${#BACKUPS[@]} - 5; i++)); do
        rm -rf "${BACKUPS[$i]}"
    done
    ok "Pruned old backups (kept 5 most recent)"
fi

# ─── Rebuild image ────────────────────────────────────────────────────────────
if $DO_BUILD; then
    step "Rebuilding Docker image: $IMAGE_NAME"
    [[ -f "$SCRIPT_DIR/Dockerfile" ]] || die "Dockerfile not found at $SCRIPT_DIR — cannot build"
    # Tag current image as rollback target before overwriting
    if docker image inspect "$IMAGE_NAME" &>/dev/null 2>&1; then
        docker tag "$IMAGE_NAME" "${IMAGE_NAME}:rollback"
        ok "Previous image tagged as ${IMAGE_NAME}:rollback"
    fi
    docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
    ok "Image rebuilt"
else
    warn "Skipping build (--no-build)"
fi

# ─── Recreate macvlan networks if missing ─────────────────────────────────────
step "Checking macvlan networks"

# Derive interface names by exact scope-link subnet match (field 3 is the dev).
# The old two-octet prefix-match awk could grab the default route's gateway IP
# instead of the interface name — this matches install.sh's robust approach.
_iface_for() { ip -o route show scope link 2>/dev/null | awk -v s="$1" '$1==s{print $3; exit}'; }
LAN1_IF=$(_iface_for "$LAN1_SUBNET")
LAN2_IF=$(_iface_for "$LAN2_SUBNET")
LAN1_IF="${LAN1_IF:-eth0}"
LAN2_IF="${LAN2_IF:-eth1}"

recreate_macvlan() {
    local name=$1 parent=$2 subnet=$3 gateway=$4 container_ip=$5
    if docker network inspect "$name" &>/dev/null; then
        ok "Network $name exists"
    else
        warn "Network $name missing (lost on reboot?) — recreating"
        # --gateway only when known; Docker defaults to the subnet's .1 otherwise
        # (cosmetic — the container routes via setuproutes.sh policy tables).
        local gw_arg=()
        [[ -n "$gateway" ]] && gw_arg=(--gateway "$gateway")
        docker network create \
            --driver macvlan \
            --subnet "$subnet" \
            "${gw_arg[@]}" \
            --ip-range "${container_ip}/30" \
            -o parent="$parent" \
            "$name"
        ok "Recreated $name (parent=$parent, gw=${gateway:-auto}, ip-range=${container_ip}/30)"
    fi
}

recreate_macvlan "macvlan-lan1" "$LAN1_IF" "$LAN1_SUBNET" "$LAN1_GATEWAY" "$LAN1_CONTAINER_IP"
recreate_macvlan "macvlan-lan2" "$LAN2_IF" "$LAN2_SUBNET" "$LAN2_GATEWAY" "$LAN2_CONTAINER_IP"

# ─── Regenerate docker-compose.yml ───────────────────────────────────────────
# Always regenerate so the compose file reflects the current .env values and
# the current lib/compose.sh template. This also covers the case where the
# file is absent (fresh clone, gitignore cleanup, first run after migration).
generate_compose

# ─── Restart container ────────────────────────────────────────────────────────
step "Restarting container"

# Graceful stop first — gives ZeroTier 15s to flush state cleanly
if docker stop --time=15 "$CONTAINER_NAME" 2>/dev/null; then
    ok "Container stopped gracefully"
else
    warn "Container was not running"
fi
# Belt-and-suspenders: clear stale PID file so zerotier-one can bind port 9993
rm -f "$DATA_DIR/zerotier-one/zerotier-one.pid"

dc -f "$SCRIPT_DIR/docker-compose.yml" up -d --force-recreate
ok "Container started"

# ─── Wait for ZeroTier to be ready ────────────────────────────────────────────
step "Waiting for ZeroTier"

ZT_READY=false
for i in $(seq 1 60); do
    if docker exec "$CONTAINER_NAME" zerotier-cli status &>/dev/null 2>&1; then
        ok "ZeroTier ready (${i}s)"
        ZT_READY=true
        break
    fi
    sleep 1
done

if ! $ZT_READY; then
    warn "ZeroTier not ready after 60s — attempting rollback"
    if docker image inspect "${IMAGE_NAME}:rollback" &>/dev/null 2>&1; then
        docker tag "${IMAGE_NAME}:rollback" "$IMAGE_NAME"
        docker stop --time=10 "$CONTAINER_NAME" 2>/dev/null || true
        rm -f "$DATA_DIR/zerotier-one/zerotier-one.pid"
        dc -f "$SCRIPT_DIR/docker-compose.yml" up -d --force-recreate
        die "Update failed — rolled back to previous image. Check: docker logs $CONTAINER_NAME"
    fi
    die "ZeroTier not ready after 60s. Check: docker logs $CONTAINER_NAME"
fi

# ─── Tuning + watchdog cron ───────────────────────────────────────────────────
# Idempotent (tagged /etc/crontab block — never adds a second job). Ensures
# existing installs that only ever run the update path also get reboot-persistent
# tuning and the offline-moon watchdog.
step "Ensuring tuning + watchdog cron"
if bash "$SCRIPT_DIR/zmoon" install-cron; then
    ok "cron present"
else
    warn "cron install failed (non-DSM host?) — add a DSM Boot-up task: /usr/local/bin/zmoon boot"
fi

# ─── Report ───────────────────────────────────────────────────────────────────
ZT_STATUS=$(docker exec "$CONTAINER_NAME" zerotier-cli status 2>/dev/null || echo "not ready")
MOON_ID=$(moon_id_of "$MOONS_DIR" || echo "pending")
# Report the 10-char world id (what `orbit` takes), not the padded filename
[[ "$MOON_ID" =~ ^0*[0-9a-fA-F]{10}$ && ${#MOON_ID} -eq 16 ]] && MOON_ID="${MOON_ID: -10}"

echo
echo -e "${G}────────────────────────────────────────────────────────────${NC}"
echo -e "${G} Update complete${NC}"
echo -e "${G}────────────────────────────────────────────────────────────${NC}"
echo
echo "  ZT Status  : $ZT_STATUS"
echo "  Moon ID    : $MOON_ID"
echo "  LAN 1      : ${LAN1_CONTAINER_IP} ($LAN1_IF)"
echo "  LAN 2      : ${LAN2_CONTAINER_IP} ($LAN2_IF)"
echo "  Backup     : $BACKUP_DIR"
echo
echo "  Verify peers:  docker exec $CONTAINER_NAME zerotier-cli listpeers"
echo "  Follow logs:   docker logs -f $CONTAINER_NAME"
echo "  Full status:   bash update.sh --status"
echo
