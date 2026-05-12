#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# ZeroTier Moon Updater — Synology DS918+
# Rebuilds the Docker image and restarts the container WITHOUT touching the
# moon identity, moons.d/, or network config. Safe to run at any time.
#
# Usage:
#   bash update.sh            — rebuild image, recreate macvlan nets if missing,
#                               restart container
#   bash update.sh --no-build — skip rebuild, just recreate nets + restart
#   bash update.sh --status   — show current status only, no changes
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# ─── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m' NC='\033[0m'
step() { echo -e "\n${B}[>]${NC} $*"; }
ok()   { echo -e "  ${G}✓${NC} $*"; }
warn() { echo -e "  ${Y}!${NC} $*"; }
die()  { echo -e "  ${R}✗${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo -i, then bash update.sh"
command -v docker &>/dev/null || die "Docker not found."

# ─── Parse args ───────────────────────────────────────────────────────────────
DO_BUILD=true
STATUS_ONLY=false
for arg in "$@"; do
    case $arg in
        --no-build)  DO_BUILD=false ;;
        --status)    STATUS_ONLY=true ;;
    esac
done

# ─── Load config ──────────────────────────────────────────────────────────────
[[ -f "$ENV_FILE" ]] || die ".env not found — run install.sh first"
# shellcheck source=/dev/null
source "$ENV_FILE"

DATA_DIR="${DATA_DIR:-/volume1/docker/zerotier}"
CONTAINER_NAME="${CONTAINER_NAME:-zerotier-moon}"
IMAGE_NAME="${IMAGE_NAME:-zerotier-moon}"

# ─── Status only ──────────────────────────────────────────────────────────────
if $STATUS_ONLY; then
    echo -e "\n${B}ZeroTier Moon Status${NC}"
    echo "  Container : $(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo 'not found')"
    echo "  ZT Status : $(docker exec "$CONTAINER_NAME" zerotier-cli status 2>/dev/null || echo 'unreachable')"
    echo "  Moon ID   : $(ls "$DATA_DIR/zerotier-one/moons.d/" 2>/dev/null | sed 's/\.moon//' || echo 'none')"
    echo "  Peers     :"
    docker exec "$CONTAINER_NAME" zerotier-cli listpeers 2>/dev/null || echo "    (unavailable)"
    exit 0
fi

# ─── Guard: verify moon identity is intact ────────────────────────────────────
step "Checking moon identity"

IDENTITY_SECRET="$DATA_DIR/zerotier-one/identity.secret"
IDENTITY_PUBLIC="$DATA_DIR/zerotier-one/identity.public"
MOONS_DIR="$DATA_DIR/zerotier-one/moons.d"

[[ -f "$IDENTITY_SECRET" ]] || die "identity.secret missing at $IDENTITY_SECRET — moon identity lost. Re-run install.sh to start fresh."
[[ -f "$IDENTITY_PUBLIC" ]] || die "identity.public missing at $IDENTITY_PUBLIC"

MOON_FILES=$(ls "$MOONS_DIR"/*.moon 2>/dev/null | wc -l)
if [[ "$MOON_FILES" -eq 0 ]]; then
    warn "No .moon files found in $MOONS_DIR — moon will be recompiled on next start (identity preserved)"
else
    MOON_ID=$(ls "$MOONS_DIR"/*.moon 2>/dev/null | head -1 | xargs basename | sed 's/\.moon//')
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

# ─── Rebuild image ────────────────────────────────────────────────────────────
if $DO_BUILD; then
    step "Rebuilding Docker image: $IMAGE_NAME"
    docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
    ok "Image rebuilt"
else
    warn "Skipping build (--no-build)"
fi

# ─── Recreate macvlan networks if missing ─────────────────────────────────────
step "Checking macvlan networks"

# Detect interfaces from .env
LAN1_IF=$(ip route | awk "/$(echo "$LAN1_SUBNET" | sed 's|/.*||' | awk -F. '{print $1"."$2}')/ {print \$3; exit}")
LAN2_IF=$(ip route | awk "/$(echo "$LAN2_SUBNET" | sed 's|/.*||' | awk -F. '{print $1"."$2}')/ {print \$3; exit}")
LAN1_IF="${LAN1_IF:-eth0}"
LAN2_IF="${LAN2_IF:-eth1}"

recreate_macvlan() {
    local name=$1 parent=$2 subnet=$3 gateway=$4
    if docker network inspect "$name" &>/dev/null; then
        ok "Network $name exists"
    else
        warn "Network $name missing (lost on reboot?) — recreating"
        docker network create \
            --driver macvlan \
            --subnet "$subnet" \
            --gateway "$gateway" \
            -o parent="$parent" \
            "$name"
        ok "Recreated $name (parent=$parent)"
    fi
}

recreate_macvlan "macvlan-lan1" "$LAN1_IF" "$LAN1_SUBNET" "$LAN1_GATEWAY"
recreate_macvlan "macvlan-lan2" "$LAN2_IF" "$LAN2_SUBNET" "$LAN2_GATEWAY"

# ─── Restart container ────────────────────────────────────────────────────────
step "Restarting container"

docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d --force-recreate
ok "Container restarted"

# ─── Wait for ZeroTier to be ready ────────────────────────────────────────────
step "Waiting for ZeroTier"

for i in $(seq 1 30); do
    if docker exec "$CONTAINER_NAME" zerotier-cli status &>/dev/null 2>&1; then
        ok "ZeroTier ready (${i}s)"
        break
    fi
    [[ $i -eq 30 ]] && { warn "ZeroTier not ready after 30s — check: docker logs $CONTAINER_NAME"; }
    sleep 1
done

# ─── Report ───────────────────────────────────────────────────────────────────
ZT_STATUS=$(docker exec "$CONTAINER_NAME" zerotier-cli status 2>/dev/null || echo "not ready")
MOON_ID=$(ls "$MOONS_DIR"/*.moon 2>/dev/null | head -1 | xargs basename 2>/dev/null | sed 's/\.moon//' || echo "pending")

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
