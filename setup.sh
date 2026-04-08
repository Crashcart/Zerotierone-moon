#!/bin/bash
# ZeroTier Moon setup script for Synology DS918+
# Run this script as root via SSH on the NAS

set -e

ZEROTIER_DIR="/volume1/docker/zerotier-moon"
TUN_SCRIPT="/usr/local/etc/rc.d/tun.sh"

# ─── Colours ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Root check ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root. Use: sudo bash setup.sh"
fi

# ─── Public IP ──────────────────────────────────────────────────────────────
if [ -z "$ZEROTIER_MOON_PUBLIC_IP" ]; then
    read -rp "Enter the public IP address of this NAS: " ZEROTIER_MOON_PUBLIC_IP
    [ -z "$ZEROTIER_MOON_PUBLIC_IP" ] && error "Public IP is required."
fi
export ZEROTIER_MOON_PUBLIC_IP

info "Using public IP: ${ZEROTIER_MOON_PUBLIC_IP}"

# ─── Enable TUN device ──────────────────────────────────────────────────────
info "Configuring /dev/net/tun..."

if [ ! -d /dev/net ]; then
    mkdir -p /dev/net
fi

if [ ! -c /dev/net/tun ]; then
    # Check if tun is already loaded as a built-in module
    if grep -q '^tun ' /proc/modules 2>/dev/null; then
        info "tun module is already loaded."
    elif ! modprobe tun 2>/dev/null; then
        # Synology uses insmod instead of modprobe
        if [ -f /lib/modules/tun.ko ]; then
            insmod /lib/modules/tun.ko || warning "Could not load tun module. Verify /lib/modules/tun.ko exists and DSM version is compatible."
        else
            warning "/lib/modules/tun.ko not found. The tun module may be compiled into the kernel or the path differs on this DSM version."
        fi
    fi
fi

# Persist TUN load across reboots (Synology-specific rc.d approach)
if [ ! -f "$TUN_SCRIPT" ]; then
    info "Creating persistent TUN boot script at ${TUN_SCRIPT}..."
    cat > "$TUN_SCRIPT" << 'EOF'
#!/bin/sh -e
[ -d /dev/net ] || mkdir -p /dev/net
[ -c /dev/net/tun ] || insmod /lib/modules/tun.ko
EOF
    chmod a+x "$TUN_SCRIPT"
fi

if [ -c /dev/net/tun ]; then
    info "/dev/net/tun is available."
else
    warning "/dev/net/tun not found – container will attempt to create it on start."
fi

# ─── Persistent storage ─────────────────────────────────────────────────────
info "Creating ZeroTier data directory: ${ZEROTIER_DIR}"
mkdir -p "${ZEROTIER_DIR}/moons.d"

# ─── Docker check ───────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    error "Docker is not installed. Install it from Synology Package Center first."
fi

# ─── Write .env file ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
info "Writing .env file..."
cat > "${SCRIPT_DIR}/.env" << EOF
ZEROTIER_MOON_PUBLIC_IP=${ZEROTIER_MOON_PUBLIC_IP}
EOF

# ─── Start container ────────────────────────────────────────────────────────
info "Starting ZeroTier Moon container..."
if ! docker compose -f "${SCRIPT_DIR}/docker-compose.yml" up -d; then
    error "Failed to start the ZeroTier Moon container. Check that Docker is running and review the output above. You can also run: docker logs zerotier-moon"
fi

# ─── Wait for identity generation ───────────────────────────────────────────
info "Waiting for ZeroTier identity to be generated..."
IDENTITY_FILE="${ZEROTIER_DIR}/identity.public"
TIMEOUT=60
ELAPSED=0

while [ ! -f "$IDENTITY_FILE" ]; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        error "Timed out waiting for ${IDENTITY_FILE}. Check container logs: docker logs zerotier-moon"
    fi
done

info "Identity file found."

# ─── Display Moon ID ────────────────────────────────────────────────────────
MOON_ID=$(docker logs zerotier-moon 2>&1 | awk '/My moon ID is/{print $NF}' | tail -1)

if [ -z "$MOON_ID" ]; then
    # Fall back to deriving from identity file
    MOON_ID=$(awk '{print $1}' "$IDENTITY_FILE")
fi

echo ""
echo "============================================================"
echo -e "  ${GREEN}ZeroTier Moon is running!${NC}"
echo "  Moon ID : ${MOON_ID}"
echo "  Public IP: ${ZEROTIER_MOON_PUBLIC_IP}"
echo ""
echo "  To join this Moon from a ZeroTier client, run:"
echo -e "    ${YELLOW}zerotier-cli orbit ${MOON_ID} ${MOON_ID}${NC}"
echo ""
echo "  Or copy the .moon file from:"
echo "    ${ZEROTIER_DIR}/moons.d/"
echo "  to the client's /var/lib/zerotier-one/moons.d/ directory."
echo "============================================================"
