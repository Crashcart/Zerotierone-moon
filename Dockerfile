FROM alpine:3.19

# Install ZeroTier and networking tools
RUN apk add --no-cache \
    zerotier-one \
    iproute2 \
    iptables \
    ip6tables \
    bash \
    curl \
    jq

# Copy entrypoint and route setup helper
COPY entrypoint.sh /entrypoint.sh
COPY config/setuproutes.sh /usr/local/bin/setuproutes.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/setuproutes.sh

# ZeroTier data directory (identity, networks, moons.d)
VOLUME ["/var/lib/zerotier-one"]

# ZeroTier UDP port
EXPOSE 9993/udp

ENTRYPOINT ["/entrypoint.sh"]
