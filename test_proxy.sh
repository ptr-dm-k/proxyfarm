#!/bin/bash
# Test ProxyFarm proxy server

PROXY="http://user1:pass1@localhost:3128"
PROXY2="http://user2:pass2@localhost:3128"

echo "=== Testing ProxyFarm Proxy ==="
echo ""

echo "Test 1: HTTP request (user1 → wwan0)"
curl -x "$PROXY" http://ifconfig.me
echo ""

echo "Test 2: HTTPS request (user1 → wwan0)"
curl -x "$PROXY" https://ifconfig.me
echo ""

echo "Test 3: HTTP request (user2 → wwan1)"
curl -x "$PROXY2" http://ifconfig.me
echo ""

echo "Test 4: HTTPS request (user2 → wwan1)"
curl -x "$PROXY2" https://ifconfig.me
echo ""

echo "Test 5: Multiple requests from user1"
for i in {1..5}; do
    echo -n "  Request $i: "
    curl -s -x "$PROXY" https://api.ipify.org
done
echo ""

echo "Test 6: Unauthorized (should fail)"
curl -x "http://wrong:wrong@localhost:3128" http://ifconfig.me
echo ""

echo "Done!"
