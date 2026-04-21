#!/bin/bash
# ZeroTier Moon Node — Synology DSM 7+ (Container Manager)
#
# branch-aware: the URL below must match the branch this file lives on.
# See .github/BRANCH_AWARE_FILES.md for the full list and promotion checklist.
#
# Synology's admin shell is sh (ash) — use this one-liner instead of bash <(...):
#   curl -fsSL https://raw.githubusercontent.com/Crashcart/Zerotierone-moon/beta/install-beta.sh -o /tmp/zt-install.sh && bash /tmp/zt-install.sh
#
# Usage: bash install.sh [ACTION] [OPTIONS]
#
#   Actions:
#     install    Set up the moon node from scratch (default)
#     update     Pull latest image and restart, preserving moon config
#     uninstall  Stop and remove the moon node
#
#   Options:
#     --auto, -a     Fully unattended (auto-select IP, skip all prompts)
#     --ip <addr>    Use this IP as the moon's stable endpoint
#     --force, -f    Force reinstall if container already exists
#     --purge        (uninstall) Also delete the data directory
#     --help, -h     Show usage

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
if docker compose version >/dev/null 2>&1; then
    DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    DC=(docker-compose)
else
    error "docker compose not found. Make sure Container Manager is installed in DSM."
fi

# ── Root check ────────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root (try: sudo bash install.sh)"
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
        if [ "$FORCE" = true ]; then
            info "Force mode: recreating container..."
        else
            read -rp "  Re-install from scratch? This will recreate the container [y/N]: " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
        fi
        info "Stopping existing container..."
        if cd "$COMPOSE_DIR" 2>/dev/null; then
            "${DC[@]}" down 2>/dev/null || docker rm -f "$CONTAINER" 2>/dev/null || true
        else
            docker rm -f "$CONTAINER" 2>/dev/null || true
        fi
    fi

    # Check /dev/net/tun
    info "Checking /dev/net/tun..."
    if [ ! -c /dev/net/tun ]; then
        warn "/dev/net/tun not found — attempting to load tun kernel module..."
        if ! modprobe tun 2>/dev/null; then
            # DSM 7 may not have modprobe — search for the module manually
            TUN_KO=$(find /lib/modules -name 'tun.ko*' 2>/dev/null | head -1)
            if [ -n "$TUN_KO" ]; then insmod "$TUN_KO" 2>/dev/null || true; fi
        fi
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
    cd "$COMPOSE_DIR" || error "Cannot cd to $COMPOSE_DIR"
    "${DC[@]}" pull
    info "Starting container..."
    "${DC[@]}" up -d
    ok "Container started"

    # Wait for daemon (30 × 2s = 60s timeout)
    info "Waiting for ZeroTier daemon..."
    for i in $(seq 1 30); do
        if docker exec "$CONTAINER" zerotier-cli info >/dev/null 2>&1; then
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

    # POSIX-compatible IP detection (no grep -P or mapfile — works on DSM 7 BusyBox)
    IPS=()
    while IFS= read -r _ip; do
        [[ -n "$_ip" ]] && IPS+=("$_ip")
    done <<< "$(ip -4 addr show 2>/dev/null \
        | awk '/inet / {split($2, a, "/"); print a[1]}' \
        | grep -v '^127\.')"

    # Fallback: use ifconfig if ip returned nothing (older DSM builds)
    if [ ${#IPS[@]} -eq 0 ] && command -v ifconfig >/dev/null 2>&1; then
        while IFS= read -r _ip; do
            [[ -n "$_ip" ]] && IPS+=("$_ip")
        done <<< "$(ifconfig 2>/dev/null \
            | awk '/inet / {gsub(/addr:/, ""); print $2}' \
            | grep -v '^127\.')"
    fi

    if [ ${#IPS[@]} -eq 0 ]; then
        error "No local IPv4 addresses found. Check network configuration."
    fi

    echo ""
    echo "  Available addresses:"
    for i in "${!IPS[@]}"; do
        echo "    $((i+1))) ${IPS[$i]}"
    done
    echo ""

    if [ -n "$STABLE_IP" ]; then
        # Explicit --ip flag
        LOCAL_IP="$STABLE_IP"
        ok "Using provided endpoint: $LOCAL_IP:9993"
    elif [ "$AUTO" = true ] || [ ${#IPS[@]} -eq 1 ]; then
        # Auto-select first IP (only option, or --auto mode)
        LOCAL_IP="${IPS[0]}"
        ok "Auto-selected endpoint: $LOCAL_IP:9993"
    else
        read -rp "  Which IP should clients use to reach this moon? [1]: " choice
        choice=${choice:-1}

        # Validate choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#IPS[@]}" ]; then
            warn "Invalid choice — defaulting to 1"
            choice=1
        fi

        LOCAL_IP="${IPS[$((choice-1))]}"
        ok "Stable endpoint: $LOCAL_IP:9993"
    fi

    # Generate, sign, and place moon config
    info "Generating moon configuration..."
    docker exec "$CONTAINER" sh -c \
        "zerotier-idtool initmoon /var/lib/zerotier-one/identity.public \
         | sed 's/\"stableEndpoints\":\[\]/\"stableEndpoints\":[\"'""${LOCAL_IP}""'\/9993\"]/' \
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
        docker exec "$CONTAINER" zerotier-cli info >/dev/null 2>&1 && break
        sleep 2
    done

    # Join ZeroTier network
    NETWORK_ID="$NETWORK"
    if [ -z "$NETWORK_ID" ]; then
        if [ "$AUTO" = true ]; then
            warn "No --network specified — moon is running but not joined to any network"
            warn "Join manually later: docker exec $CONTAINER zerotier-cli join <network_id>"
        else
            echo ""
            info "To relay traffic, this moon must join your ZeroTier network."
            echo "  Find your network ID at https://my.zerotier.com or in your controller."
            echo ""
            read -rp "  ZeroTier Network ID (16-char hex, or leave blank to skip): " NETWORK_ID
        fi
    fi

    if [ -n "$NETWORK_ID" ]; then
        # Validate: 16 hex characters
        if [[ "$NETWORK_ID" =~ ^[0-9a-fA-F]{16}$ ]]; then
            info "Joining network $NETWORK_ID ..."
            docker exec "$CONTAINER" zerotier-cli join "$NETWORK_ID"
            ok "Network joined — authorize this node in your ZeroTier controller"
        else
            warn "Invalid network ID '$NETWORK_ID' (expected 16 hex chars) — skipping join"
            NETWORK_ID=""
        fi
    fi

    # Done
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   Moon node is running!                              ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Moon ID   : ${BOLD}$MOON_ID${NC}"
    echo -e "  Endpoint  : $LOCAL_IP:9993"
    [ -n "$NETWORK_ID" ] && echo -e "  Network   : $NETWORK_ID"
    echo -e "  Data dir  : $DATA_DIR"
    echo ""
    echo -e "  Run this on each client device to orbit this moon:"
    echo ""
    echo -e "  ${GREEN}zerotier-cli orbit $MOON_ID $MOON_ID${NC}"
    echo ""
    [ -n "$NETWORK_ID" ] && echo -e "  ${YELLOW}Remember:${NC} Authorize this moon node in your ZeroTier controller."
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

    cd "$COMPOSE_DIR" || error "Cannot cd to $COMPOSE_DIR"
    info "Pulling latest image..."
    "${DC[@]}" pull

    info "Recreating container..."
    "${DC[@]}" up -d --force-recreate

    # Wait for daemon
    info "Waiting for daemon..."
    for i in $(seq 1 20); do
        docker exec "$CONTAINER" zerotier-cli info >/dev/null 2>&1 && break
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
            if cd "$COMPOSE_DIR"; then
                "${DC[@]}" down 2>/dev/null || docker rm -f "$CONTAINER"
            else
                docker rm -f "$CONTAINER"
            fi
        else
            docker rm -f "$CONTAINER"
        fi
        ok "Container removed"
    else
        warn "Container '$CONTAINER' not found — may already be removed"
    fi

    # Remove image?
    if [ "$AUTO" = true ]; then
        info "Auto mode: keeping Docker image"
    else
        read -rp "Remove Docker image ($IMAGE)? [y/N]: " remove_image
        if [[ "$remove_image" =~ ^[Yy]$ ]]; then
            if docker rmi "$IMAGE" 2>/dev/null; then
                ok "Image removed"
            else
                warn "Image not found or still in use by another container"
            fi
        fi
    fi

    # Remove data?
    if [ "$PURGE" = true ]; then
        warn "Purge mode: removing data directory..."
        rm -rf "$DATA_DIR"
        ok "Data directory removed"
    elif [ "$AUTO" = true ]; then
        ok "Auto mode: data directory kept at $DATA_DIR"
    else
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
    echo -e "Usage: ${BOLD}bash install.sh [ACTION] [OPTIONS]${NC}"
    echo ""
    echo "  Actions:"
    echo "    install    Set up ZeroTier moon node (default)"
    echo "    update     Pull latest image and restart, preserving moon config"
    echo "    uninstall  Stop and remove the moon node"
    echo ""
    echo "  Options:"
    echo "    --auto, -a          Run fully unattended (auto-select IP, skip prompts)"
    echo "    --network <id>      Join this ZeroTier network (16-char hex ID)"
    echo "    --ip <addr>         Use this IP as the stable endpoint"
    echo "    --force, -f         Force reinstall if container already exists"
    echo "    --purge             (uninstall only) Also delete data directory"
    echo "    --help, -h          Show this help"
    echo ""
    echo "  Examples:"
    echo "    bash install.sh                                         # Interactive install"
    echo "    bash install.sh --auto --network abcdef1234567890       # Fully automatic"
    echo "    bash install.sh --auto --network abc... --ip 10.0.1.50  # Auto + specific IP"
    echo "    bash install.sh update                                  # Pull latest, keep config"
    echo "    bash install.sh uninstall --purge                       # Remove everything"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
ACTION="install"
AUTO=false
FORCE=false
PURGE=false
STABLE_IP=""
NETWORK=""

while [ $# -gt 0 ]; do
    case "$1" in
        install|update|uninstall) ACTION="$1" ;;
        --auto|-a)  AUTO=true ;;
        --force|-f) FORCE=true ;;
        --purge)    PURGE=true ;;
        --ip)
            [ -n "${2:-}" ] || error "--ip requires an address (e.g. --ip 192.168.1.100)"
            STABLE_IP="$2"; shift ;;
        --network)
            [ -n "${2:-}" ] || error "--network requires a 16-char network ID"
            NETWORK="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

# Auto-detect non-interactive shell (e.g. curl | bash)
if [ ! -t 0 ]; then
    warn "Non-interactive shell detected — enabling --auto mode"
    AUTO=true
fi

# --auto implies --force
[ "$AUTO" = true ] && FORCE=true

case "$ACTION" in
    install)   do_install   ;;
    update)    do_update    ;;
    uninstall) do_uninstall ;;
esac
