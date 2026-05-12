#!/bin/bash
set -euo pipefail

ZT_HOME=/var/lib/zerotier-one
ZT_TIMEOUT=30

log()  { echo "[zerotier-moon] $*"; }
die()  { echo "[zerotier-moon] ERROR: $*" >&2; exit 1; }

# ─── Create data directory if missing ─────────────────────────────────────────
mkdir -p "$ZT_HOME/moons.d"

# ─── Start ZeroTier daemon ─────────────────────────────────────────────────────
log "Starting ZeroTier daemon..."
zerotier-one "$ZT_HOME" &
ZT_PID=$!

# Wait for daemon to be ready
log "Waiting for ZeroTier to be ready..."
for i in $(seq 1 $ZT_TIMEOUT); do
    if zerotier-cli status &>/dev/null 2>&1; then
        log "ZeroTier is ready (${i}s)"
        break
    fi
    if [[ $i -eq $ZT_TIMEOUT ]]; then
        die "ZeroTier did not start within ${ZT_TIMEOUT}s"
    fi
    sleep 1
done

# ─── Conntrack UDP timeout ────────────────────────────────────────────────────
# net.netfilter sysctls live in the HOST network namespace, not the container's.
# These writes will silently fail in a namespaced container on DSM 7 even with
# SYS_ADMIN. The correct fix is to set these on the host via install.sh (which
# writes them to /etc/sysctl.conf). We attempt here as a best-effort for
# environments where the container does have host-ns access (e.g. --net=host).
if sysctl -w net.netfilter.nf_conntrack_udp_timeout=300 2>/dev/null; then
    sysctl -w net.netfilter.nf_conntrack_udp_timeout_stream=300 2>/dev/null || true
    log "conntrack UDP timeout set to 300s"
else
    log "NOTE: conntrack UDP timeout not writable from container — set by install.sh on host"
fi

# ─── Apply iptables rules ──────────────────────────────────────────────────────
if [[ -f /etc/iptables/rules.v4 ]]; then
    log "Applying iptables rules (NOTRACK + FORWARD + scoped MASQUERADE)..."
    iptables-restore < /etc/iptables/rules.v4 || log "WARNING: iptables-restore failed (may need NET_ADMIN/NET_RAW cap)"
fi

# ─── Apply dual-NIC routing ────────────────────────────────────────────────────
if [[ -f "$ZT_HOME/setuproutes.sh" ]]; then
    log "Applying dual-NIC routing rules..."
    bash "$ZT_HOME/setuproutes.sh" || log "WARNING: setuproutes.sh failed — check interface names"
fi

# ─── Send gratuitous ARP to clear stale ARP cache on LAN switches ─────────────
# After a container restart, LAN switches hold the previous MAC mapping for
# up to 300s. Gratuitous ARP clears that immediately.
for iface in eth0 eth1; do
    ip addr show dev "$iface" &>/dev/null 2>&1 || continue
    ip_addr=$(ip -4 addr show dev "$iface" | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
    if [[ -n "${ip_addr:-}" ]]; then
        arping -A -c 3 -I "$iface" "$ip_addr" 2>/dev/null || true
        log "Sent gratuitous ARP for $ip_addr on $iface"
    fi
done

# ─── Join ZeroTier network(s) ─────────────────────────────────────────────────
if [[ -n "${NETWORK_IDS:-}" ]]; then
    IFS=';' read -ra NETS <<< "$NETWORK_IDS"
    for NET in "${NETS[@]}"; do
        NET="$(echo "$NET" | tr -d '[:space:]')"
        [[ -z "$NET" ]] && continue
        log "Joining network: $NET"
        zerotier-cli join "$NET" || log "WARNING: Failed to join $NET"
    done
fi

# ─── Generate moon (first run only) ───────────────────────────────────────────
if [[ "${GENERATE_MOON:-false}" == "true" ]]; then
    MOON_JSON="$ZT_HOME/moon.json"

    if [[ ! -f "$MOON_JSON" ]]; then
        log "Generating moon template..."
        # Wait for identity to be generated
        for i in $(seq 1 10); do
            [[ -f "$ZT_HOME/identity.public" ]] && break
            sleep 1
        done
        [[ -f "$ZT_HOME/identity.public" ]] || die "identity.public not found after 10s"

        zerotier-idtool initmoon "$ZT_HOME/identity.public" > "$MOON_JSON"

        # Inject stable endpoints from environment
        if [[ -n "${MOON_ENDPOINTS:-}" ]]; then
            ENDPOINTS_JSON=$(echo "$MOON_ENDPOINTS" | tr ',' '\n' | jq -R . | jq -s .)
            jq --argjson eps "$ENDPOINTS_JSON" \
                '.roots[0].stableEndpoints = $eps' \
                "$MOON_JSON" > "${MOON_JSON}.tmp" && mv "${MOON_JSON}.tmp" "$MOON_JSON"
            log "Stable endpoints set: $MOON_ENDPOINTS"
        else
            log "WARNING: MOON_ENDPOINTS not set — edit $MOON_JSON manually and run genmoon"
        fi
    fi

    # Compile moon if json exists but .moon file does not
    MOON_ID=$(jq -r '.id' "$MOON_JSON" 2>/dev/null || true)
    if [[ -n "$MOON_ID" ]]; then
        MOON_FILE="$ZT_HOME/moons.d/$(printf '%010x' "0x${MOON_ID}").moon"
        if [[ ! -f "$MOON_FILE" ]]; then
            log "Compiling moon $MOON_ID..."
            cd "$ZT_HOME"
            zerotier-idtool genmoon "$MOON_JSON"
            mv ./*.moon "$ZT_HOME/moons.d/" 2>/dev/null || true
            log "Moon compiled and placed in moons.d/"
        fi

        # Orbit our own moon
        zerotier-cli orbit "$MOON_ID" "$MOON_ID" 2>/dev/null || true
        log "Moon ID: $MOON_ID"
        log "Clients: zerotier-cli orbit $MOON_ID $MOON_ID"
    fi
fi

# ─── Set fq qdisc on ZeroTier interface ───────────────────────────────────────
# Must run AFTER network join — the zt* interface is created only once ZeroTier
# has joined a network. On first-ever start, the interface may not exist yet;
# subsequent restarts will find it immediately.
# fq (fair queuing) replaces the default fq_codel, providing per-flow pacing
# and keeping latency low under load (reduces bufferbloat on the ZT interface).
ZT_IF=$(ip link show 2>/dev/null | awk -F': ' '/^[0-9]+: zt/{print $2; exit}')
if [[ -n "${ZT_IF:-}" ]]; then
    tc qdisc replace dev "$ZT_IF" root fq 2>/dev/null || true
    log "Set fq qdisc on $ZT_IF"
else
    log "NOTE: No ZeroTier interface found yet — fq qdisc will apply on next restart after network join"
fi

# ─── Log active local.conf ────────────────────────────────────────────────────
if [[ -f "$ZT_HOME/local.conf" ]]; then
    log "local.conf loaded: $(tr -d '\n' < "$ZT_HOME/local.conf")"
fi

# ─── Keep container alive — wait on ZeroTier process ─────────────────────────
log "ZeroTier moon running (PID $ZT_PID)"
wait $ZT_PID
