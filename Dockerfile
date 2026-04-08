FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        gnupg \
        iproute2 \
        iptables \
        jq \
        ca-certificates && \
    mkdir -p /usr/share/keyrings && \
    curl -fsSL 'https://raw.githubusercontent.com/zerotier/ZeroTierOne/main/doc/contact%40zerotier.com.gpg' \
        | gpg --dearmor -o /usr/share/keyrings/zerotier-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/zerotier-archive-keyring.gpg] https://download.zerotier.com/debian/jammy jammy main" \
        > /etc/apt/sources.list.d/zerotier.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends zerotier-one && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/var/lib/zerotier-one"]

EXPOSE 9993/udp

ENTRYPOINT ["/entrypoint.sh"]
