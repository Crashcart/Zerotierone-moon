#!/bin/bash
# Shared host-level kernel + NIC tuning for the ZeroTier moon.
#
# Sourced by install.sh (install time — persists to /etc/sysctl.conf AND applies
# live) and by `zmoon boot` (re-applies live on every reboot). The values live
# here ONCE so the installer and the boot re-apply can never drift.
#
# Why boot re-apply is needed on DSM: Synology does not reliably re-read
# /etc/sysctl.conf on boot, and GRO/TSO/GSO offload always resets. Without a
# boot hook the moon comes back after a reboot with small socket buffers, no
# NIC offload, and the default 30s conntrack UDP timeout (< ZeroTier's ~25s
# keepalive under jitter) — slower and prone to periodic UDP cutouts. These
# net.core.* / net.netfilter.* keys also cannot be set from inside the
# container's network namespace, so the host is the only place they take effect.

# Live-settable host sysctls. IPv4/IPv6 forwarding is applied by apply_host_tuning
# too; install.sh additionally persists forwarding to /etc/sysctl.conf.
HOST_SYSCTLS=(
    "net.core.rmem_max=8388608"
    "net.core.wmem_max=8388608"
    "net.core.netdev_max_backlog=5000"
    "net.ipv4.udp_mem=102400 873800 8388608"
    "net.netfilter.nf_conntrack_udp_timeout=300"
    "net.netfilter.nf_conntrack_udp_timeout_stream=300"
)

# iface_for SUBNET → name of the interface whose scope-link route matches SUBNET.
iface_for() { ip -o route show scope link 2>/dev/null | awk -v s="$1" '$1==s{print $3; exit}'; }

# apply_host_tuning IF1 IF2 → live-apply the sysctls, forwarding, and NIC offload.
# Idempotent and quiet: safe to run on every boot. Never fails the caller.
apply_host_tuning() {
    local if1="${1:-}" if2="${2:-}" param key val
    for param in "${HOST_SYSCTLS[@]}"; do
        key="${param%%=*}"; val="${param#*=}"
        sysctl -w "${key}=${val}" >/dev/null 2>&1 || true
    done
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true
    if [ -n "$if1" ]; then ethtool -K "$if1" gro on tso on gso on >/dev/null 2>&1 || true; fi
    if [ -n "$if2" ]; then ethtool -K "$if2" gro on tso on gso on >/dev/null 2>&1 || true; fi
}
