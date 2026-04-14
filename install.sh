#!/bin/bash
# ZeroTier Moon Node — Synology DSM 7+ (Container Manager)
#
# Synology's admin shell is sh (ash) — use this one-liner instead of bash <(...):
#   curl -fsSL https://raw.githubusercontent.com/Crashcart/Zerotierone-moon/main/install.sh -o /tmp/zt-install.sh && bash /tmp/zt-install.sh
#
# Usage: bash install.sh [install|update|uninstall]
#   install    Set up the moon node from scratch (default)
#   update     Pull latest image and restart, preserving moon config
#   uninstall  Stop and remove the moon node

set -e

# ── Config ────────────────────────────────────────────────────────────────────
COMPOSE_DIR="/volume1/docker/zerotierone-moon"
DATA_DIR="$COMPOSE_DIR/data"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
CONTAINER="zerotierone-moon"
IMAGE="zyclonite/zerotier:latest"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERR ]${NC}  $*"; exit 1; }

# ── Detect docker compose command ─────────────────────────────────────────────
if docker compose version &>/dev/null 2>&1; then
    DC="docker compose"
elif command -v docker-compose &>/dev/null 2>&1; then
    DC="docker-compose"
else
    error "docker compose not found. Make sure Container Manager is installed in DSM."
fi

# ─────────────────────────────────────────────────────────────────────────────
# INSTALL
# ─────────────────────────────────────────────────────────────────────────────
do_install() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   ZeroTier Moon Node — Install           ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""

    # Guard: already installed?
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
        warn "Container '${CONTAINER}' already exists."
        read -rp "  Re-install from scratch? This will recreate the container [y/N]: " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
        info "Stopping existing container..."
        cd "$COMPOSE_DIR" 2>/dev/null && $DC down 2>/dev/null || docker rm -f "$CONTAINER" 2>/dev/null || true
    fi

    # Check /dev/net/tun
    info "Checking /dev/net/tun..."
    if [ ! -c /dev/net/tun ]; then
        warn "/dev/net/tun not found — attempting to load tun kernel module..."
        modprobe tun 2>/dev/null || insmod /lib/modules/tun.ko 2>/dev/null || true
        [ -c /dev/net/tun ] || error "/dev/net/tun still missing after modprobe. Check DSM kernel modules."
    fi
    ok "/dev/net/tun available"

    # Create directories
    info "Creating data directory at $DATA_DIR ..."
    mkdir -p "$DATA_DIR"
    ok "Directory ready"

    # Write docker-compose.yml
    info "Writing $COMPOSE_FILE ..."
    cat > "$COMPOSE_FILE" <<'YAML'
version: '3'

services:
  zerotier:
    image: zyclonite/zerotier:latest
    container_name: zerotierone-moon
    restart: unless-stopped
    network_mode: host
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
    devices:
      - /dev/net/tun
    volumes:
      - /volume1/docker/zerotierone-moon/data:/var/lib/zerotier-one
YAML
    ok "docker-compose.yml written"

    # Pull and start
    info "Pulling image $IMAGE ..."
    cd "$COMPOSE_DIR"
    $DC pull
    info "Starting container..."
    $DC up -d
    ok "Container started"

    # Wait for daemon (30 × 2s = 60s timeout)
    info "Waiting for ZeroTier daemon..."
    for i in $(seq 1 30); do
        if docker exec "$CONTAINER" zerotier-cli info &>/dev/null 2>&1; then
            break
        fi
        sleep 2
        if [ "$i" -eq 30 ]; then
            error "Daemon did not start within 60 s. Check: docker logs $CONTAINER"
        fi
    done
    ok "Daemon ready"

    # Get moon ID
    MOON_ID=$(docker exec "$CONTAINER" zerotier-cli info | awk '{print $3}')
    ok "Moon ID: $MOON_ID"

    # Detect local IPs
    echo ""
    info "Detecting local IP addresses..."
    mapfile -t IPS < <(ip -4 addr show | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | grep -v '^127\.')

    if [ ${#IPS[@]} -eq 0 ]; then
        error "No local IPv4 addresses found. Check network configuration."
    fi

    echo ""
    echo "  Available addresses:"
    for i in "${!IPS[@]}"; do
        echo "    $((i+1))) ${IPS[$i]}"
    done
    echo ""
    read -rp "  Which IP should clients use to reach this moon? [1]: " choice
    choice=${choice:-1}

    # Validate choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#IPS[@]}" ]; then
        warn "Invalid choice — defaulting to 1"
        choice=1
    fi

    LOCAL_IP="${IPS[$((choice-1))]}"
    ok "Stable endpoint: $LOCAL_IP:9993"

    # Generate, sign, and place moon config
    info "Generating moon configuration..."
    docker exec "$CONTAINER" sh -c \
        "zerotier-idtool initmoon /var/lib/zerotier-one/identity.public \
         | sed 's/\"stableEndpoints\":\[\]/\"stableEndpoints\":[\"'"${LOCAL_IP}"'\/9993\"]/' \
         > /var/lib/zerotier-one/moon.json"

    info "Signing moon..."
    docker exec "$CONTAINER" sh -c \
        "cd /var/lib/zerotier-one && \
         zerotier-idtool genmoon moon.json && \
         mkdir -p moons.d && \
         mv *.moon moons.d/"

    info "Restarting container to activate moon..."
    docker restart "$CONTAINER"

    # Brief wait after restart
    sleep 5
    for i in $(seq 1 10); do
        docker exec "$CONTAINER" zerotier-cli info &>/dev/null 2>&1 && break
        sleep 2
    done

    # Done
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   Moon node is running!                              ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Moon ID   : ${BOLD}$MOON_ID${NC}"
    echo -e "  Endpoint  : $LOCAL_IP:9993"
    echo -e "  Data dir  : $DATA_DIR"
    echo ""
    echo -e "  Run this on each client device to orbit this moon:"
    echo ""
    echo -e "  ${GREEN}zerotier-cli orbit $MOON_ID $MOON_ID${NC}"
    echo ""
    echo -e "  Verify with: ${CYAN}zerotier-cli listpeers${NC}  (look for role MOON)"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# UPDATE
# ─────────────────────────────────────────────────────────────────────────────
do_update() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   ZeroTier Moon Node — Update            ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""

    [ -f "$COMPOSE_FILE" ] || error "No installation found at $COMPOSE_DIR. Run: bash install.sh install"

    cd "$COMPOSE_DIR"
    info "Pulling latest image..."
    $DC pull

    info "Recreating container..."
    $DC up -d --force-recreate

    # Wait for daemon
    info "Waiting for daemon..."
    for i in $(seq 1 20); do
        docker exec "$CONTAINER" zerotier-cli info &>/dev/null 2>&1 && break
        sleep 2
    done

    STATUS=$(docker exec "$CONTAINER" zerotier-cli info 2>/dev/null || echo "unavailable")
    MOON_ID=$(echo "$STATUS" | awk '{print $3}')

    ok "Update complete"
    echo ""
    echo -e "  Status  : $STATUS"
    echo -e "  Moon ID : ${BOLD}$MOON_ID${NC}  (unchanged — clients remain orbited)"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# UNINSTALL
# ─────────────────────────────────────────────────────────────────────────────
do_uninstall() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   ZeroTier Moon Node — Uninstall         ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""

    # Stop and remove container
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
        info "Stopping and removing container..."
        if [ -f "$COMPOSE_FILE" ]; then
            cd "$COMPOSE_DIR" && $DC down 2>/dev/null || docker rm -f "$CONTAINER"
        else
            docker rm -f "$CONTAINER"
        fi
        ok "Container removed"
    else
        warn "Container '$CONTAINER' not found — may already be removed"
    fi

    # Remove image?
    read -rp "Remove Docker image ($IMAGE)? [y/N]: " remove_image
    if [[ "$remove_image" =~ ^[Yy]$ ]]; then
        docker rmi "$IMAGE" 2>/dev/null && ok "Image removed" || warn "Image not found or still in use by another container"
    fi

    # Remove data?
    echo ""
    echo -e "  ${YELLOW}Warning:${NC} The data directory contains this moon's ZeroTier identity."
    echo -e "  Deleting it means all client devices will need to orbit a new moon ID."
    echo ""
    read -rp "Delete data directory ($DATA_DIR)? [y/N]: " remove_data
    if [[ "$remove_data" =~ ^[Yy]$ ]]; then
        rm -rf "$DATA_DIR"
        ok "Data directory removed"
    else
        ok "Data directory kept at $DATA_DIR"
    fi

    # Remove compose file
    [ -f "$COMPOSE_FILE" ] && rm -f "$COMPOSE_FILE" && ok "docker-compose.yml removed"

    echo ""
    ok "Uninstall complete."
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Usage
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo -e "Usage: ${BOLD}bash install.sh [install|update|uninstall]${NC}"
    echo ""
    echo "  install    Set up ZeroTier moon node (default)"
    echo "  update     Pull latest image and restart, preserving moon config"
    echo "  uninstall  Stop and remove the moon node"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
ACTION="${1:-install}"

case "$ACTION" in
    install)   do_install   ;;
    update)    do_update    ;;
    uninstall) do_uninstall ;;
    *)         usage; exit 1 ;;
esac
