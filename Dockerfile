# zerotier-one was dropped from Alpine's community repo after v3.17 — it is NOT
# in 3.18/3.19/3.20/3.21. v3.17 community ships zerotier-one 1.10.2-r0, which
# predates the 1.14.0 listnetworks regression (issue #2324) and is a stable,
# proven root/moon build. Pinned here so `apk add zerotier-one` resolves.
FROM alpine:3.17

# Install ZeroTier and networking tools
RUN apk add --no-cache \
    zerotier-one \
    iproute2 \
    iptables \
    ip6tables \
    bash \
    curl \
    jq \
    iputils

# Copy entrypoint and route setup helper
COPY entrypoint.sh /entrypoint.sh
COPY config/setuproutes.sh /usr/local/bin/setuproutes.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/setuproutes.sh

# ZeroTier data directory (identity, networks, moons.d)
VOLUME ["/var/lib/zerotier-one"]

# ZeroTier UDP port
EXPOSE 9993/udp

ENTRYPOINT ["/entrypoint.sh"]
