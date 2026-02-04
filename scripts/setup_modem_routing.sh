#!/bin/bash
# Setup multipath routing through LTE modems

set -e

echo "=== Setting up multipath routing through modems ==="
echo ""

# Get gateway IPs from wwan interfaces (first IP in subnet is usually gateway)
echo "Getting gateway IPs from wwan interfaces..."
IP0=$(ip -4 addr show wwan0 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "")
IP1=$(ip -4 addr show wwan1 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "")

# Calculate gateway (usually .1 in the subnet)
if [ -n "$IP0" ]; then
    GW0=$(echo $IP0 | sed 's/\.[0-9]*$/\.1/')
else
    GW0=""
fi

if [ -n "$IP1" ]; then
    GW1=$(echo $IP1 | sed 's/\.[0-9]*$/\.1/')
else
    GW1=""
fi

echo "wwan0: ${IP0:-not found} -> gateway: ${GW0:-none}"
echo "wwan1: ${IP1:-not found} -> gateway: ${GW1:-none}"
echo ""

# Remove old WiFi default route with low metric
echo "Removing old WiFi default route..."
ip route del default via 192.168.50.1 dev wlan0 metric 600 2>/dev/null || true

# Add WiFi as backup with high metric
echo "Adding WiFi as backup route (metric 1000)..."
ip route add default via 192.168.50.1 dev wlan0 metric 1000 2>/dev/null || true

# Enable multipath hashing (L4)
echo "Enabling L4 multipath hashing..."
sysctl -w net.ipv4.fib_multipath_hash_policy=1 >/dev/null

# Setup multipath or single path default route
if [ -n "$GW0" ] && [ -n "$GW1" ]; then
    echo "Setting up multipath default route through both modems..."
    ip route add default scope global \
        nexthop via $GW0 dev wwan0 weight 1 \
        nexthop via $GW1 dev wwan1 weight 1 2>/dev/null || \
    (
        echo "Multipath route already exists, replacing..."
        ip route replace default scope global \
            nexthop via $GW0 dev wwan0 weight 1 \
            nexthop via $GW1 dev wwan1 weight 1
    )
    echo "✓ Multipath route added with both modems"
elif [ -n "$GW0" ]; then
    echo "Setting up route through wwan0 only..."
    ip route add default via $GW0 dev wwan0 metric 100 2>/dev/null || \
        ip route replace default via $GW0 dev wwan0 metric 100
    echo "✓ Route added through wwan0"
elif [ -n "$GW1" ]; then
    echo "Setting up route through wwan1 only..."
    ip route add default via $GW1 dev wwan1 metric 100 2>/dev/null || \
        ip route replace default via $GW1 dev wwan1 metric 100
    echo "✓ Route added through wwan1"
else
    echo "ERROR: No modem gateways found!"
    exit 1
fi

# Flush route cache
echo "Flushing route cache..."
ip route flush cache

echo ""
echo "=== Current default routes ==="
ip route show default

echo ""
echo "=== Testing connection ==="
echo -n "Your IP: "
curl -s -m 10 http://ifconfig.me || echo "Connection test failed"

echo ""
echo ""
echo "=== Setup Complete ==="
