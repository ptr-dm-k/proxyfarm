#!/bin/bash
# Test load balancing through proxy

PROXY="http://138.2.138.243:3128"

echo "=== Testing Load Balancing ==="
echo ""
echo "Method 1: Different hosts (best for seeing balancing)"
echo "------------------------------------------------------"

HOSTS=(
    "http://ifconfig.me"
    "http://api.ipify.org"
    "http://ipinfo.io/ip"
    "http://icanhazip.com"
    "http://ident.me"
    "http://ifconfig.co"
)

for host in "${HOSTS[@]}"; do
    IP=$(curl -s -x "$PROXY" --max-time 5 "$host" 2>/dev/null | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
    echo "$host → $IP"
done

echo ""
echo "Method 2: Same host with delays"
echo "--------------------------------"

for i in {1..10}; do
    IP=$(curl -s -x "$PROXY" --max-time 5 http://ifconfig.me 2>/dev/null)
    echo "Request $i: $IP"
    sleep 1
done

echo ""
echo "Method 3: Statistics"
echo "--------------------"

declare -A ip_count

for i in {1..30}; do
    IP=$(curl -s -x "$PROXY" --max-time 5 http://ifconfig.me 2>/dev/null)
    ((ip_count[$IP]++))
    printf "."
done

echo ""
echo ""
echo "IP Distribution:"
for ip in "${!ip_count[@]}"; do
    count=${ip_count[$ip]}
    percentage=$((count * 100 / 30))
    echo "$ip: $count requests ($percentage%)"
done

echo ""
echo "Expected: ~50/50 distribution between two IPs"
echo "Note: Due to connection pooling, distribution may not be perfect"
