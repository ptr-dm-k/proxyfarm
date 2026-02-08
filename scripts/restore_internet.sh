#!/bin/bash
# Emergency script to restore internet connection on Orange Pi
# Run this script ON THE ORANGE PI if internet is down

echo "=== Orange Pi Internet Restoration ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Must run as root"
    echo "Usage: sudo $0"
    exit 1
fi

echo "Current network status:"
echo "----------------------"
ip addr show wlan0 2>/dev/null | grep "inet " || echo "wlan0: No IP"
ip addr show wwan0 2>/dev/null | grep "inet " || echo "wwan0: No IP"
ip addr show wwan1 2>/dev/null | grep "inet " || echo "wwan1: No IP"

echo ""
echo "Current routing table:"
echo "---------------------"
ip route show

echo ""
echo "Testing connectivity:"
echo "--------------------"
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    echo "✓ Internet is working (can ping 8.8.8.8)"
    echo ""
    echo "Current outgoing IP:"
    curl -s --max-time 5 ifconfig.me
    echo ""
    exit 0
else
    echo "✗ No internet connection"
fi

echo ""
echo "=== Restoring Internet ==="
echo ""

# Step 1: Remove all default routes
echo "1. Removing all default routes..."
while ip route del default 2>/dev/null; do
    echo "   Removed a default route"
done

# Step 2: Add WiFi default route
echo "2. Adding WiFi default route..."
if ip route add default via 192.168.50.1 dev wlan0 metric 600; then
    echo "   ✓ WiFi route added"
else
    echo "   ✗ Failed to add WiFi route"
    echo ""
    echo "Trying to fix WiFi connection..."

    # Check if WiFi interface exists
    if ! ip link show wlan0 &>/dev/null; then
        echo "   ERROR: wlan0 interface not found!"
        exit 1
    fi

    # Try to bring WiFi up
    ip link set wlan0 up
    sleep 2

    # Check if WiFi has IP
    if ! ip addr show wlan0 | grep -q "inet "; then
        echo "   WiFi has no IP address. Trying to reconnect..."

        # Get WiFi connection name
        WIFI_CONN=$(nmcli -t -f NAME,TYPE connection show --active | grep wireless | head -1 | cut -d: -f1)

        if [ -n "$WIFI_CONN" ]; then
            echo "   Found WiFi connection: $WIFI_CONN"
            echo "   Reconnecting..."
            nmcli connection down "$WIFI_CONN"
            sleep 2
            nmcli connection up "$WIFI_CONN"
            sleep 5

            # Try adding route again
            ip route add default via 192.168.50.1 dev wlan0 metric 600
        else
            echo "   ERROR: No active WiFi connection found!"
            echo "   Available connections:"
            nmcli connection show
            exit 1
        fi
    fi
fi

# Step 3: Flush route cache
echo "3. Flushing route cache..."
ip route flush cache

# Step 4: Test connectivity
echo "4. Testing internet connection..."
echo ""

if ping -c 2 8.8.8.8 &>/dev/null; then
    echo "✓ SUCCESS: Can ping 8.8.8.8"
    echo ""
    echo "Testing HTTP..."
    if OUTGOING_IP=$(curl -s --max-time 5 ifconfig.me); then
        echo "✓ SUCCESS: Internet is working!"
        echo ""
        echo "Current outgoing IP: $OUTGOING_IP"
        echo ""
    else
        echo "✗ WARNING: Ping works but HTTP doesn't"
        echo "This might be a DNS or firewall issue"
    fi
else
    echo "✗ FAILED: Still no internet connection"
    echo ""
    echo "Additional troubleshooting:"
    echo "1. Check NetworkManager status: systemctl status NetworkManager"
    echo "2. Check WiFi signal: nmcli device wifi list"
    echo "3. Check DNS: cat /etc/resolv.conf"
    echo "4. Try manual ping: ping 192.168.50.1"
    exit 1
fi

echo ""
echo "=== Internet Restored ==="
echo ""
echo "Current routing table:"
ip route show
echo ""
echo "NOTE: This is using WiFi as default route."
echo "To set up multipath routing through modems, run:"
echo "  cd /root/repo/proxyfarm/scripts"
echo "  sudo ./install.sh"
echo ""
