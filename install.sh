#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# ZeroTier Moon Installer — Synology DS918+
# Installs and configures a ZeroTier moon node with dual-NIC support.
#
# Usage:
#   1. Copy .env.example to .env and fill in your values
#   2. Enable SSH in DSM: Control Panel → Terminal & SNMP → Enable SSH
#   3. ssh admin@<NAS_IP>, then: sudo -i
#   4. cd /path/to/this/repo && bash install.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Shared compose generator
# shellcheck source=lib/compose.sh
source "$SCRIPT_DIR/lib/compose.sh"
# Shared host tuning (sysctls + NIC offload) — single source of truth for install + boot
# shellcheck source=lib/tuning.sh
source "$SCRIPT_DIR/lib/tuning.sh"

# ─── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m' NC='\033[0m'
step() { echo -e "\n${B}[>]${NC} $*"; }
ok()   { echo -e "  ${G}✓${NC} $*"; }
warn() { echo -e "  ${Y}!${NC} $*"; }
die()  { echo -e "  ${R}✗${NC} $*" >&2; exit 1; }

# Read a prompt from the CONTROLLING TERMINAL, not stdin. Under
# `curl … | sudo bash`, stdin is the exhausted curl pipe — a plain `read`
# hits EOF there and set -e kills the whole install at the first prompt.
# Returns 1 only when no terminal exists at all (fully non-interactive run).
tty_read() {   # tty_read "prompt" VARNAME
    local __prompt="$1" __var="$2" __in
    if [[ -t 0 ]]; then
        read -rp "$__prompt" __in || return 1
    elif { exec 3</dev/tty; } 2>/dev/null; then
        read -u 3 -rp "$__prompt" __in || { exec 3<&-; return 1; }
        exec 3<&-
    else
        return 1
    fi
    printf -v "$__var" '%s' "$__in"
}
ask()  { tty_read "    $1: " "$2" || die "$2 is required but no terminal is available — create/edit .env and re-run"; }

# ─── Root check ───────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run as root: sudo -i, then bash install.sh"

# ─── Docker check ─────────────────────────────────────────────────────────────
command -v docker &>/dev/null || die "Docker not found. Install Container Manager from DSM Package Center first."

# Detect docker compose v2 plugin vs docker-compose v1 binary (DSM 7.0/7.1)
if docker compose version &>/dev/null 2>&1; then
    dc() { docker compose "$@"; }
elif command -v docker-compose &>/dev/null 2>&1; then
    dc() { docker-compose "$@"; }
else
    die "Neither 'docker compose' nor 'docker-compose' found — install Docker Compose"
fi

# ─── Load or create .env ──────────────────────────────────────────────────────
step "Configuration"

_is_ipv4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    ok "Loaded config from .env"

    # Sanitize gateway values — a stale .env may contain an interface name
    # instead of an IP (from an older run with broken detection). Re-detect
    # from live routing table and patch .env in place so subsequent runs are clean.
    _if_gateway() { ip -o route show default 2>/dev/null | awk -v d="$1" 'index($0,"dev "d){for(i=1;i<=NF;i++)if($i=="via"){print $(i+1);exit}}'; }
    _iface_for()  { ip -o route show scope link 2>/dev/null | awk -v s="$1" '$1==s{print $3; exit}'; }
    _sanitize_gw() {
        local varname="$1" val="${!1:-}"
        [[ -z "$val" ]] && return 0           # already blank — nothing to do
        _is_ipv4 "$val" && return 0           # looks like an IP — keep it
        local iface detected
        iface=$(_iface_for "${!2:-}")         # derive interface from subnet var
        iface="${iface:-$3}"                  # fall back to eth0/eth1
        detected=$(_if_gateway "$iface")
        warn "$varname='$val' is not a valid IP — re-detected: ${detected:-<none>}"
        printf -v "$varname" '%s' "$detected"
        local tmp; tmp=$(mktemp)
        sed "s|^${varname}=.*|${varname}=${detected}|" "$ENV_FILE" > "$tmp" && mv "$tmp" "$ENV_FILE"
        [[ -n "$detected" ]] && ok "$varname updated to $detected in .env"
    }
    _sanitize_gw LAN1_GATEWAY LAN1_SUBNET eth0
    _sanitize_gw LAN2_GATEWAY LAN2_SUBNET eth1
    # Existing .env is authoritative — its gateway values (user-entered on first
    # install) are preserved. Reinstalls never overwrite saved config.
else
    # ── Auto-detect network config from ip route / ip addr ────────────────────
    _if_subnet()  { ip route show dev "$1" proto kernel 2>/dev/null | awk 'NR==1{print $1}'; }
    # Gateway: only the address after "via" on this interface's default route.
    # A bare "default dev ethX" (no via) yields nothing — gateway stays empty.
    _if_gateway() { ip -o route show default 2>/dev/null | awk -v d="$1" 'index($0,"dev "d){for(i=1;i<=NF;i++)if($i=="via"){print $(i+1);exit}}'; }
    _if_ip()      { ip addr show "$1" 2>/dev/null | awk '/inet /{sub("/.*","",$2); print $2}' | head -1; }

    D1_SUBNET=$(_if_subnet eth0);  D1_GW=$(_if_gateway eth0);  D1_IP=$(_if_ip eth0)
    D2_SUBNET=$(_if_subnet eth1);  D2_GW=$(_if_gateway eth1);  D2_IP=$(_if_ip eth1)
    # Suggest .253 on each subnet as the container IP (avoids collision with NAS or router)
    D1_CIP="${D1_IP%.*}.253"; D2_CIP="${D2_IP%.*}.253"
    # Detect public IP (5s timeout; blank = user can fill in later)
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || true)

    # Accept detected values automatically; only prompt for what detection missed.
    LAN1_SUBNET="$D1_SUBNET"; LAN1_GATEWAY="$D1_GW"; LAN1_CONTAINER_IP="$D1_CIP"
    LAN2_SUBNET="$D2_SUBNET"; LAN2_GATEWAY="$D2_GW"; LAN2_CONTAINER_IP="$D2_CIP"
    ZT_PUBLIC_ENDPOINT="$PUBLIC_IP"

    echo
    ok "Detected  eth0 → ${LAN1_SUBNET:-?}  gw ${LAN1_GATEWAY:-?}  container ${LAN1_CONTAINER_IP:-?}"
    ok "Detected  eth1 → ${LAN2_SUBNET:-?}  gw ${LAN2_GATEWAY:-?}  container ${LAN2_CONTAINER_IP:-?}"
    [[ -n "$ZT_PUBLIC_ENDPOINT" ]] && ok "Public IP → $ZT_PUBLIC_ENDPOINT"
    echo

    # Prompt only when auto-detection came back empty — fall back to manual entry.
    _need() {
        local prompt="$1" varname="$2"
        [[ -n "${!varname}" ]] && return 0
        local input=""
        tty_read "    ${prompt}: " input \
            || die "${varname} could not be auto-detected and no terminal is available — set it in .env and re-run"
        printf -v "$varname" '%s' "$input"
    }

    # ── Auto-detect ZeroTier Network ID from any prior install ────────────────
    # 1. A migrated old .env (get-latest-dev.sh leaves it at <repo>.old/.env)
    # 2. The ZeroTier data dir — joined networks live in networks.d/<id>.conf
    ZT_NETWORK_ID=""
    for old_env in "$SCRIPT_DIR.old/.env" /volume1/docker/zerotierone-moon.old/.env; do
        if [[ -f "$old_env" ]]; then
            _found=$(grep -E '^ZT_NETWORK_ID=' "$old_env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
            [[ "$_found" =~ ^[0-9a-fA-F]{16}$ ]] && { ZT_NETWORK_ID="$_found"; ok "Network ID found in $old_env"; break; }
        fi
    done
    if [[ -z "$ZT_NETWORK_ID" ]]; then
        shopt -s nullglob
        for conf in /volume1/docker/zerotier/zerotier-one/networks.d/*.conf; do
            _found=$(basename "$conf" .conf)
            [[ "$_found" =~ ^[0-9a-fA-F]{16}$ ]] && { ZT_NETWORK_ID="$_found"; ok "Network ID found in existing ZeroTier data: $ZT_NETWORK_ID"; break; }
        done
        shopt -u nullglob
    fi

    # Only prompt if no prior install was found — otherwise fully auto.
    [[ -z "$ZT_NETWORK_ID" ]] && ask "ZeroTier Network ID (from my.zerotier.com)" ZT_NETWORK_ID

    # Subnet + container IP are required (macvlan needs them); gateways are
    # optional — a second NIC serving same-L2 clients often has no gateway,
    # and setuproutes.sh tolerates an empty one.
    _need "LAN 1 subnet (e.g. 192.168.1.0/24)"        LAN1_SUBNET
    _need "LAN 1 container IP (e.g. 192.168.1.253)"   LAN1_CONTAINER_IP
    _need "LAN 2 subnet (e.g. 172.16.0.0/24)"         LAN2_SUBNET
    _need "LAN 2 container IP (e.g. 172.16.0.253)"    LAN2_CONTAINER_IP
    # LAN gateways and ZT_PUBLIC_ENDPOINT stay as detected (may be blank)

    DATA_DIR="/volume1/docker/zerotier"
    CONTAINER_NAME="zerotier-moon"
    IMAGE_NAME="zerotier-moon"

    cat > "$ENV_FILE" <<EOF
ZT_NETWORK_ID=${ZT_NETWORK_ID}
MOON_MODE=true
ZT_PUBLIC_ENDPOINT=${ZT_PUBLIC_ENDPOINT}
LAN1_SUBNET=${LAN1_SUBNET}
LAN1_GATEWAY=${LAN1_GATEWAY}
LAN1_CONTAINER_IP=${LAN1_CONTAINER_IP}
LAN2_SUBNET=${LAN2_SUBNET}
LAN2_GATEWAY=${LAN2_GATEWAY}
LAN2_CONTAINER_IP=${LAN2_CONTAINER_IP}
DATA_DIR=${DATA_DIR}
CONTAINER_NAME=${CONTAINER_NAME}
IMAGE_NAME=${IMAGE_NAME}
AUTO_UPDATE=false
AUTO_UPDATE_BRANCH=dev
EOF
    ok "Saved config to .env"
fi

# Validate required values
[[ -n "${ZT_NETWORK_ID:-}"       ]] || die "ZT_NETWORK_ID is not set"
[[ "${ZT_NETWORK_ID}" =~ ^[0-9a-fA-F]{16}$ ]] || die "ZT_NETWORK_ID must be exactly 16 hex characters (got: ${ZT_NETWORK_ID})"
[[ -n "${LAN1_SUBNET:-}"         ]] || die "LAN1_SUBNET is not set"
[[ -n "${LAN1_CONTAINER_IP:-}"   ]] || die "LAN1_CONTAINER_IP is not set"
[[ -n "${LAN2_SUBNET:-}"         ]] || die "LAN2_SUBNET is not set"
[[ -n "${LAN2_CONTAINER_IP:-}"   ]] || die "LAN2_CONTAINER_IP is not set"
# LAN gateways are optional — only used for per-table default routes in
# setuproutes.sh; a same-L2 second NIC may legitimately have none.

DATA_DIR="${DATA_DIR:-/volume1/docker/zerotier}"
CONTAINER_NAME="${CONTAINER_NAME:-zerotier-moon}"
IMAGE_NAME="${IMAGE_NAME:-zerotier-moon}"

# ─── Derive interface names from subnets ──────────────────────────────────────
# Match the kernel scope-link route whose destination equals the subnet and
# return its device name (field 3). This is exact — the old prefix-match on
# "192.168" wrongly grabbed the default route's gateway IP as the interface.
_iface_for() { ip -o route show scope link 2>/dev/null | awk -v s="$1" '$1==s{print $3; exit}'; }
LAN1_IF=$(_iface_for "$LAN1_SUBNET")
LAN2_IF=$(_iface_for "$LAN2_SUBNET")

# Fall back to eth0/eth1 if detection fails
LAN1_IF="${LAN1_IF:-eth0}"
LAN2_IF="${LAN2_IF:-eth1}"

ok "LAN 1 interface: $LAN1_IF ($LAN1_SUBNET)"
ok "LAN 2 interface: $LAN2_IF ($LAN2_SUBNET)"

# ─── Step 1: IP Forwarding ────────────────────────────────────────────────────
step "Enabling IP forwarding"

if grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
    ok "Already set in /etc/sysctl.conf"
else
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    ok "Added to /etc/sysctl.conf"
fi

sysctl -w net.ipv4.ip_forward=1 &>/dev/null
ok "IPv4 forwarding active"

if grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf 2>/dev/null; then
    ok "net.ipv6.conf.all.forwarding already set in /etc/sysctl.conf"
else
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    ok "Added net.ipv6.conf.all.forwarding=1 to /etc/sysctl.conf"
fi

sysctl -w net.ipv6.conf.all.forwarding=1 &>/dev/null
ok "IPv6 forwarding active"

# Host-level kernel tuning — persisted to /etc/sysctl.conf AND applied live.
# The values (socket buffers ~2× BDP for ZT on 1GbE; conntrack UDP timeout 300s
# vs ZT's ~25s keepalive) live in lib/tuning.sh so the boot re-apply
# (`zmoon boot`) never drifts from what the installer wrote. net.netfilter /
# net.core keys cannot be set from the container namespace — the host is the
# only place they take effect, and DSM does not reliably re-read this file on
# reboot, which is why `zmoon boot` re-applies them (wire it to a Boot-up task).
for param in "${HOST_SYSCTLS[@]}"; do
    key="${param%%=*}"
    if grep -q "^${key}" /etc/sysctl.conf 2>/dev/null; then
        ok "$key already set in /etc/sysctl.conf"
    else
        echo "$param" >> /etc/sysctl.conf
        ok "Set $param"
    fi
done
sysctl -p &>/dev/null || true

# Live-apply buffers/forwarding + GRO/TSO/GSO NIC offload (hardware packet batching)
apply_host_tuning "$LAN1_IF" "$LAN2_IF"
ok "NIC offload tuned ($LAN1_IF, $LAN2_IF)"

# ─── Step 2: Create data directories ─────────────────────────────────────────
step "Creating data directories under $DATA_DIR"

mkdir -p \
    "$DATA_DIR/zerotier-one/moons.d" \
    "$DATA_DIR/iproute2" \
    "$DATA_DIR/iptables"

ok "Directories ready"

# ─── Step 3: Generate config files ────────────────────────────────────────────
step "Writing config files"

# setuproutes.sh — templated from .env values
cat > "$DATA_DIR/zerotier-one/setuproutes.sh" <<EOF
#!/bin/sh
# Auto-generated by install.sh — dual-NIC policy routing for DS918+

IF1="${LAN1_IF}"
IF2="${LAN2_IF}"

IP1="${LAN1_CONTAINER_IP}"
IP2="${LAN2_CONTAINER_IP}"

P1="${LAN1_GATEWAY}"
P2="${LAN2_GATEWAY}"

P1_NET="${LAN1_SUBNET}"
P2_NET="${LAN2_SUBNET}"

TBL1="ISP_1"
TBL2="ISP_2"

# Flush ALL existing rules for each table before re-adding.
# 'ip rule del table X' removes only ONE matching rule per call, so loop
# until no more rules match — prevents accumulation across container restarts.
while ip rule del table \$TBL1 2>/dev/null; do true; done
while ip rule del table \$TBL2 2>/dev/null; do true; done

# Subnet return-path rules
ip rule add from \$P1_NET table \$TBL1 priority 100 2>/dev/null || true
ip rule add from \$P2_NET table \$TBL2 priority 101 2>/dev/null || true

# Container-IP rules — ZeroTier daemon outbound (keepalives, handshakes)
# is sourced from the container's own IP, not a client subnet address
ip rule add from \$IP1 table \$TBL1 priority 98 2>/dev/null || true
ip rule add from \$IP2 table \$TBL2 priority 99 2>/dev/null || true

# Per-table routes
ip route replace \$P1_NET dev \$IF1 src \$IP1 table \$TBL1 2>/dev/null || true
ip route replace default via \$P1 table \$TBL1 2>/dev/null || true

ip route replace \$P2_NET dev \$IF2 src \$IP2 table \$TBL2 2>/dev/null || true
ip route replace default via \$P2 table \$TBL2 2>/dev/null || true

# Main table fallback — needed for ZeroTier to reach public planets/roots
ip route replace default via \$P1 metric 200 2>/dev/null || true

echo "[setuproutes] Applied (LAN1=\$IF1 \$IP1, LAN2=\$IF2 \$IP2)"
EOF
chmod +x "$DATA_DIR/zerotier-one/setuproutes.sh"
ok "setuproutes.sh"

# rt_tables
cat > "$DATA_DIR/iproute2/rt_tables" <<'EOF'
255    local
254    main
253    default
0      unspec
101    ISP_1
102    ISP_2
EOF
ok "rt_tables"

# rules.v4 — with NOTRACK to bypass conntrack for ZeroTier UDP.
# iptables-restore is ATOMIC: one bad line aborts the whole restore. In
# particular -i (input iface) is ILLEGAL in nat/POSTROUTING — instead we
# mark ZT-forwarded packets in mangle/FORWARD and match the mark in nat.
cat > "$DATA_DIR/iptables/rules.v4" <<EOF
# Bypass conntrack for ZeroTier UDP — prevents 30s timeout expiring between
# ZeroTier keepalives (~25s), which causes brief cutouts under jitter.
*raw
-A PREROUTING -p udp --dport 9993 -j NOTRACK
-A OUTPUT -p udp --sport 9993 -j NOTRACK
COMMIT

# Mark traffic forwarded FROM the ZeroTier overlay. The mark persists into
# the nat POSTROUTING chain (which cannot match -i directly).
*mangle
-A FORWARD -i zt+ -j MARK --set-mark 0x2a
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
COMMIT

# Allow forwarding between ZeroTier overlay and physical NICs.
# Docker macvlan does not inject FORWARD ACCEPT rules automatically.
# NOTRACK'd flows appear as UNTRACKED state, so the ctstate ESTABLISHED
# rule does not match them — the explicit zt+/eth interface rules do.
*filter
-A FORWARD -i zt+ -o ${LAN1_IF} -j ACCEPT
-A FORWARD -i zt+ -o ${LAN2_IF} -j ACCEPT
-A FORWARD -i ${LAN1_IF} -o zt+ -j ACCEPT
-A FORWARD -i ${LAN2_IF} -o zt+ -j ACCEPT
-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
COMMIT

# MASQUERADE scoped to ZeroTier-forwarded traffic via the 0x2a mark set
# above. The second rule NATs traffic egressing the ZT interface itself.
*nat
-A POSTROUTING -m mark --mark 0x2a -j MASQUERADE
-A POSTROUTING -o zt+ -j MASQUERADE
COMMIT
EOF
ok "rules.v4"

# rules.v6 — IPv6 FORWARD rules. ip6tables-restore applies these on every
# container start. No *nat table — IPv6 uses global unicast addresses.
# ICMPv6 MUST be permitted for NDP, PMTU discovery, and Router Advertisements.
cat > "$DATA_DIR/iptables/rules.v6" <<EOF
*mangle
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
COMMIT

*filter
-A FORWARD -i zt+ -o ${LAN1_IF} -j ACCEPT
-A FORWARD -i zt+ -o ${LAN2_IF} -j ACCEPT
-A FORWARD -i ${LAN1_IF} -o zt+ -j ACCEPT
-A FORWARD -i ${LAN2_IF} -o zt+ -j ACCEPT
-A FORWARD -p icmpv6 -j ACCEPT
-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
COMMIT
EOF
ok "rules.v6"

# local.conf — copy tuning config (pins port, TCP fallback, interface blacklist)
cp "$SCRIPT_DIR/config/local.conf" "$DATA_DIR/local.conf"
ok "local.conf"

# ─── Step 4: Build Docker image ───────────────────────────────────────────────
step "Building Docker image: $IMAGE_NAME"

docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
ok "Image built: $IMAGE_NAME"

# ─── Step 5: Create macvlan Docker networks ───────────────────────────────────
step "Creating macvlan Docker networks"

create_macvlan() {
    local name=$1 parent=$2 subnet=$3 gateway=$4 container_ip=$5
    if docker network inspect "$name" &>/dev/null; then
        warn "Network $name already exists — skipping"
    else
        # Scope Docker's IP allocator to a /30 anchored at the container IP.
        # This prevents Docker from handing out IPs to other containers that
        # would conflict with real hosts on the LAN.
        # --gateway only when known; Docker defaults to the subnet's .1 otherwise
        # (cosmetic for us — the container routes via setuproutes.sh policy tables).
        local gw_arg=()
        [[ -n "$gateway" ]] && gw_arg=(--gateway "$gateway")
        docker network create \
            --driver macvlan \
            --subnet "$subnet" \
            "${gw_arg[@]}" \
            --ip-range "${container_ip}/30" \
            -o parent="$parent" \
            "$name"
        ok "Created $name (parent=$parent, $subnet, gw=${gateway:-auto}, ip-range=${container_ip}/30)"
    fi
}

create_macvlan "macvlan-lan1" "$LAN1_IF" "$LAN1_SUBNET" "$LAN1_GATEWAY" "$LAN1_CONTAINER_IP"
create_macvlan "macvlan-lan2" "$LAN2_IF" "$LAN2_SUBNET" "$LAN2_GATEWAY" "$LAN2_CONTAINER_IP"

# ─── Step 6: Write final docker-compose.yml ───────────────────────────────────
step "Writing docker-compose.yml"
generate_compose
ok "docker-compose.yml written"

# ─── Step 6b: Install zmoon to PATH ──────────────────────────────────────────
step "Installing zmoon CLI"
chmod +x "$SCRIPT_DIR/zmoon"
ln -sf "$SCRIPT_DIR/zmoon" /usr/local/bin/zmoon
ok "zmoon installed → /usr/local/bin/zmoon (run 'zmoon update' from anywhere)"

# ─── Step 7: Start the container ─────────────────────────────────────────────
step "Starting container"

# Stop and remove any existing container with same name
if docker inspect "$CONTAINER_NAME" &>/dev/null; then
    warn "Existing container found — removing"
    docker rm -f "$CONTAINER_NAME"
fi

dc -f "$SCRIPT_DIR/docker-compose.yml" up -d
ok "Container started: $CONTAINER_NAME"

# ─── Step 8: Wait and report ─────────────────────────────────────────────────
step "Waiting for ZeroTier to initialise"

sleep 5

ZT_STATUS=$(docker exec "$CONTAINER_NAME" zerotier-cli status 2>/dev/null || echo "not ready yet")
ok "ZeroTier status: $ZT_STATUS"

NODE_ID=$(docker exec "$CONTAINER_NAME" zerotier-cli status 2>/dev/null | awk '{print $3}' || echo "unknown")

echo
echo -e "${G}────────────────────────────────────────────────────────────${NC}"
echo -e "${G} ZeroTier Moon installed successfully${NC}"
echo -e "${G}────────────────────────────────────────────────────────────${NC}"
echo
echo "  Node ID     : $NODE_ID"
echo "  LAN 1       : $LAN1_CONTAINER_IP ($LAN1_IF)"
echo "  LAN 2       : $LAN2_CONTAINER_IP ($LAN2_IF)"
echo "  Data dir    : $DATA_DIR"
echo
echo "  Next steps:"
echo "  1. Wait ~30s for the moon to compile its identity, then get the exact,"
echo "     ready-to-paste client commands (Moon ID + network filled in):"
echo "       zmoon connect"
echo "  2. Lock in speed + stability across reboots (pick one):"
echo "       zmoon install-cron          — auto re-apply tuning via DSM cron"
echo "       …or DSM Task Scheduler → Boot-up task (root): zmoon boot"
echo
echo "  Update (one command, from anywhere):"
echo "    zmoon update"
echo
echo "  Other useful commands:"
echo "    zmoon connect      — client join instructions for this moon"
echo "    zmoon status       — ZT status + peers"
echo "    zmoon doctor       — 13-point health check"
echo "    zmoon web          — browser console (status + one-click update)"
echo "    zmoon logs         — follow container logs"
echo
