#!/bin/sh
# Policy routing for DS918+ dual-NIC ZeroTier gateway
# Ensures traffic sourced from each subnet exits via the correct interface.
#
# Edit these values to match your network before deploying.
# This file is placed in /var/lib/zerotier-one/ and runs automatically
# on container start via ddeitterick/zerotier-gateway.

IF1="eth0"
IF2="eth1"

IP1="192.168.1.253"     # Container IP on LAN 1
IP2="172.16.x.253"      # Container IP on LAN 2

P1="192.168.1.1"        # Gateway LAN 1
P2="172.16.x.1"         # Gateway LAN 2

P1_NET="192.168.1.0/24"
P2_NET="172.16.x.0/24"

TBL1="ISP_1"
TBL2="ISP_2"

ip route add $P1_NET dev $IF1 src $IP1 table $TBL1
ip route add default via $P1 table $TBL1

ip route add $P2_NET dev $IF2 src $IP2 table $TBL2
ip route add default via $P2 table $TBL2

ip rule add from $P1_NET table $TBL1
ip rule add from $P2_NET table $TBL2
