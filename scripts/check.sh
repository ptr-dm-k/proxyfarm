#!/bin/bash
# System diagnostic script for ProxyFarm

echo "========================================"
echo "   ProxyFarm System Diagnostics"
echo "========================================"
echo ""

echo "=== System Info ==="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo "Uptime: $(uptime -p)"
echo ""

echo "=== IP Addresses ==="
ip -4 addr show | grep -E "^[0-9]+:|inet " | sed 's/^[0-9]*: /  /' | grep -v "127.0.0.1"
echo ""

echo "=== Routing Table ==="
ip route show | sed 's/^/  /'
echo ""

echo "=== Default Routes (Detailed) ==="
ip route show default | sed 's/^/  /'
echo ""

echo "=== Modem List ==="
mmcli -L 2>/dev/null | grep -E "Modem|No modems" | sed 's/^/  /'
echo ""

echo "=== Modem Status ==="
for modem_id in 0 1; do
  echo "  Modem $modem_id:"
  if mmcli -m $modem_id &>/dev/null; then
    STATE=$(mmcli -m $modem_id | grep "state:" | awk -F': ' '{print $2}')
    SIGNAL=$(mmcli -m $modem_id | grep "signal quality:" | awk -F': ' '{print $2}')
    OPERATOR=$(mmcli -m $modem_id | grep "operator name:" | awk -F': ' '{print $2}')
    echo "    State: $STATE"
    echo "    Signal: $SIGNAL"
    echo "    Operator: $OPERATOR"
  else
    echo "    Not found"
  fi
  echo ""
done

echo "=== Bearer Info ==="
for bearer_id in 0 1; do
  echo "  Bearer $bearer_id:"
  if mmcli -b $bearer_id &>/dev/null; then
    IP=$(mmcli -b $bearer_id | grep "IP address:" | awk '{print $3}')
    GW=$(mmcli -b $bearer_id | grep "gateway:" | awk '{print $2}')
    DNS=$(mmcli -b $bearer_id | grep "DNS:" | awk '{for(i=2;i<=NF;i++) printf "%s ", $i; print ""}')
    echo "    IP: $IP"
    echo "    Gateway: $GW"
    echo "    DNS: $DNS"
  else
    echo "    Not found"
  fi
  echo ""
done

echo "=== Network Connections ==="
nmcli connection show --active | sed 's/^/  /'
echo ""

echo "=== Squid Status ==="
if systemctl is-active --quiet squid; then
  echo "  Status: Running ✓"
  PORT_CHECK=$(netstat -tlnp 2>/dev/null | grep ":3128" | wc -l)
  if [ $PORT_CHECK -gt 0 ]; then
    echo "  Port 3128: Listening ✓"
  else
    echo "  Port 3128: Not listening ✗"
  fi
else
  echo "  Status: Stopped ✗"
fi
echo ""

echo "=== FastAPI Status ==="
if systemctl is-active --quiet proxyfarm 2>/dev/null; then
  echo "  Status: Running ✓"
else
  echo "  Status: Not installed or stopped"
fi
echo ""

echo "=== VPN Tunnel ==="
if ip addr show tun0 &>/dev/null; then
  echo "  Status: Connected ✓"
  VPN_IP=$(ip -4 addr show tun0 | grep inet | awk '{print $2}')
  echo "  IP: $VPN_IP"
else
  echo "  Status: Not connected ✗"
fi
echo ""

echo "=== Testing Outgoing IPs ==="
echo -n "  Default route: "
TIMEOUT=5
DEFAULT_IP=$(timeout $TIMEOUT curl -s --max-time $TIMEOUT ifconfig.me 2>/dev/null)
if [ -n "$DEFAULT_IP" ]; then
  echo "$DEFAULT_IP"
  # Check if it's a modem IP (91.151.x.x) or WiFi (188.169.x.x)
  if echo "$DEFAULT_IP" | grep -q "^91\.151\."; then
    echo "    ✓ Using modem IP (correct)"
  elif echo "$DEFAULT_IP" | grep -q "^188\.169\."; then
    echo "    ✗ Using WiFi IP (should be modem IP)"
  fi
else
  echo "Failed (timeout)"
fi

echo -n "  wwan0: "
WWAN0_IP=$(timeout $TIMEOUT curl -s --max-time $TIMEOUT --interface wwan0 ifconfig.me 2>/dev/null)
if [ -n "$WWAN0_IP" ]; then
  echo "$WWAN0_IP ✓"
else
  echo "Failed"
fi

echo -n "  wwan1: "
WWAN1_IP=$(timeout $TIMEOUT curl -s --max-time $TIMEOUT --interface wwan1 ifconfig.me 2>/dev/null)
if [ -n "$WWAN1_IP" ]; then
  echo "$WWAN1_IP ✓"
else
  echo "Failed"
fi
echo ""

echo "=== Proxy Test ==="
if [ -n "$DEFAULT_IP" ]; then
  echo -n "  Via local proxy: "
  PROXY_IP=$(timeout $TIMEOUT curl -s --max-time $TIMEOUT -x http://localhost:3128 ifconfig.me 2>/dev/null)
  if [ -n "$PROXY_IP" ]; then
    echo "$PROXY_IP"
    if [ "$PROXY_IP" = "$DEFAULT_IP" ]; then
      echo "    (same as default route)"
    fi
  else
    echo "Failed"
  fi
fi
echo ""

echo "=== Recent Errors ==="
echo "  NetworkManager:"
journalctl -u NetworkManager --since "5 minutes ago" --no-pager -n 3 2>/dev/null | grep -i error | sed 's/^/    /' || echo "    No errors"

echo "  ModemManager:"
journalctl -u ModemManager --since "5 minutes ago" --no-pager -n 3 2>/dev/null | grep -i error | sed 's/^/    /' || echo "    No errors"

echo "  Squid:"
journalctl -u squid --since "5 minutes ago" --no-pager -n 3 2>/dev/null | grep -i error | sed 's/^/    /' || echo "    No errors"
echo ""

echo "========================================"
echo "   Diagnostic Complete"
echo "========================================"
