#!/bin/bash
# Shared docker-compose.yml generator.
# Source this file; call generate_compose after loading .env.
# Both install.sh and update.sh use this so the compose template stays in one place.

generate_compose() {
    cat > "$SCRIPT_DIR/docker-compose.yml" <<EOF
# Generated $(date '+%Y-%m-%d %H:%M:%S') by zmoon/install.sh — do not edit manually.
# To regenerate: zmoon update
services:
  zerotier:
    image: ${IMAGE_NAME}
    container_name: ${CONTAINER_NAME}
    restart: always
    devices:
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
      - NET_RAW
      - SYS_ADMIN
    # Only network-namespaced sysctls belong here. net.core.* (rmem_max,
    # wmem_max, netdev_max_backlog) are HOST-global on the DSM kernel — runc
    # cannot set them in the container netns and aborts container init with
    # "open /proc/sys/net/core/wmem_max: no such file or directory". They are
    # applied on the host by install.sh (/etc/sysctl.conf) instead. The
    # net.ipv4.udp_* values below ARE namespaced and safe to set per-container.
    sysctls:
      net.ipv4.udp_rmem_min: 8192
      net.ipv4.udp_wmem_min: 8192
    healthcheck:
      test: ["CMD", "zerotier-cli", "status"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    networks:
      macvlan-lan1:
        ipv4_address: ${LAN1_CONTAINER_IP}
      macvlan-lan2:
        ipv4_address: ${LAN2_CONTAINER_IP}
    # NOTE: 'ports' has no effect under macvlan networking — Docker does not
    # create DNAT rules for macvlan containers. Forward UDP 9993 on the
    # upstream router directly to ${LAN1_CONTAINER_IP}.
    volumes:
      - ${DATA_DIR}/zerotier-one:/var/lib/zerotier-one
      - ${DATA_DIR}/iptables:/etc/iptables
      - ${DATA_DIR}/iproute2/rt_tables:/etc/iproute2/rt_tables
      - ${DATA_DIR}/local.conf:/var/lib/zerotier-one/local.conf:ro
    environment:
      - NETWORK_IDS=${ZT_NETWORK_ID}
      - GENERATE_MOON=true
      - MOON_ENDPOINTS=${LAN1_CONTAINER_IP}/9993,${LAN2_CONTAINER_IP}/9993${ZT_PUBLIC_ENDPOINT:+,${ZT_PUBLIC_ENDPOINT}/9993}

networks:
  macvlan-lan1:
    external: true
  macvlan-lan2:
    external: true
EOF
}
