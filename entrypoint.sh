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

# ─── Apply iptables rules ──────────────────────────────────────────────────────
if [[ -f /etc/iptables/rules.v4 ]]; then
    log "Applying iptables rules..."
    iptables-restore < /etc/iptables/rules.v4 || log "WARNING: iptables-restore failed (may need NET_ADMIN cap)"
fi

# ─── Apply dual-NIC routing ────────────────────────────────────────────────────
if [[ -f "$ZT_HOME/setuproutes.sh" ]]; then
    log "Applying dual-NIC routing rules..."
    bash "$ZT_HOME/setuproutes.sh" || log "WARNING: setuproutes.sh failed — check interface names"
fi

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

# ─── Keep container alive — wait on ZeroTier process ─────────────────────────
log "ZeroTier moon running (PID $ZT_PID)"
wait $ZT_PID
