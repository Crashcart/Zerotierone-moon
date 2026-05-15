# Alpine 3.21 ships zerotier-one 1.14.x+ which is past the Synology listnetworks bug.
# Switching from 3.19 ensures we get a post-1.14.0 package with key fixes.
FROM alpine:3.21

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
