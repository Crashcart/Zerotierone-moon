#!/bin/bash
set -e

ZT_HOME="/var/lib/zerotier-one"
ZT_PORT="${ZT_PORT:-9993}"

# Start ZeroTier One daemon in background
zerotier-one -d -p"${ZT_PORT}" "${ZT_HOME}"

# Wait for the daemon to generate the identity
echo "Waiting for ZeroTier identity..."
until [ -f "${ZT_HOME}/identity.secret" ]; do
    sleep 1
done

NODE_ID=$(cat "${ZT_HOME}/identity.public" | cut -d: -f1)
echo "ZeroTier Node ID: ${NODE_ID}"

# Generate moon configuration if not already present
if [ ! -f "${ZT_HOME}/moons.d/${NODE_ID}.moon" ]; then
    if [ -z "${ZT_PUBLIC_IP}" ]; then
        echo "WARNING: ZT_PUBLIC_IP is not set. Moon will be generated without a stable endpoint."
        echo "         Set ZT_PUBLIC_IP to your server's public IP address for a functional moon."
    fi

    echo "Generating moon configuration..."
    cd "${ZT_HOME}"
    zerotier-idtool initmoon identity.public > moon.json

    # Inject the public IP/port into the moon config using jq
    if [ -n "${ZT_PUBLIC_IP}" ]; then
        jq --arg endpoint "${ZT_PUBLIC_IP}/${ZT_PORT}" \
            '.roots[0].stableEndpoints = [$endpoint]' moon.json > moon.tmp.json && \
            mv moon.tmp.json moon.json
    fi

    zerotier-idtool genmoon moon.json
    mkdir -p "${ZT_HOME}/moons.d"
    mv ./*.moon "${ZT_HOME}/moons.d/"
    echo "Moon file created: $(ls "${ZT_HOME}/moons.d/")"
fi

echo ""
echo "====================================================="
echo "  ZeroTier Moon is running"
echo "  Node ID : ${NODE_ID}"
echo "  Port    : ${ZT_PORT}/udp"
if [ -n "${ZT_PUBLIC_IP}" ]; then
    MOON_ID=$(ls "${ZT_HOME}/moons.d/" | sed 's/\.moon$//')
    echo "  Moon ID : ${MOON_ID}"
    echo ""
    echo "  On client nodes run:"
    echo "    zerotier-cli orbit ${MOON_ID} ${MOON_ID}"
fi
echo "====================================================="
echo ""

# Keep the container running by waiting on the ZeroTier daemon process
wait $(cat "${ZT_HOME}/zerotier-one.pid")
