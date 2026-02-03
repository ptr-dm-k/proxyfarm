#!/bin/bash
set -e

echo "=== Squid Proxy Setup for LTE Modems ==="

# Configuration
SQUID_PORT=3128
VPN_NETWORK="10.8.0.0/24"  # OpenVPN default network
SQUID_CONF="/etc/squid/squid.conf"
SQUID_CONF_TEMPLATE="/etc/squid/squid.conf.template"

# Install Squid if not present
if ! command -v squid &> /dev/null; then
    echo "Installing Squid..."
    apt-get update
    apt-get install -y squid
fi

echo "Detecting wwan interfaces and IP addresses..."

# Collect all wwan interfaces with IP addresses
declare -a WWAN_IPS
declare -a WWAN_IFACES

for iface in /sys/class/net/wwan*; do
    if [ -d "$iface" ]; then
        IFACE_NAME=$(basename "$iface")
        IP=$(ip -4 addr show "$IFACE_NAME" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

        if [ -n "$IP" ]; then
            echo "  Found: $IFACE_NAME -> $IP"
            WWAN_IPS+=("$IP")
            WWAN_IFACES+=("$IFACE_NAME")
        fi
    fi
done

if [ ${#WWAN_IPS[@]} -eq 0 ]; then
    echo "ERROR: No wwan interfaces with IP addresses found!"
    exit 1
fi

echo "Found ${#WWAN_IPS[@]} active modem(s)"

# Generate Squid configuration
echo "Generating Squid configuration..."

cat > "$SQUID_CONF" <<'EOF'
# Squid configuration for ProxyFarm
# Auto-generated - DO NOT EDIT MANUALLY

# Network ACLs
acl SSL_ports port 443
acl Safe_ports port 80          # http
acl Safe_ports port 21          # ftp
acl Safe_ports port 443         # https
acl Safe_ports port 70          # gopher
acl Safe_ports port 210         # wais
acl Safe_ports port 1025-65535  # unregistered ports
acl Safe_ports port 280         # http-mgmt
acl Safe_ports port 488         # gss-http
acl Safe_ports port 591         # filemaker
acl Safe_ports port 777         # multiling http
acl CONNECT method CONNECT

# VPN network access
EOF

echo "acl vpn_network src $VPN_NETWORK" >> "$SQUID_CONF"

cat >> "$SQUID_CONF" <<'EOF'

# Access rules
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager
http_access allow vpn_network
http_access allow localhost
http_access deny all

# Listening port
EOF

echo "http_port $SQUID_PORT" >> "$SQUID_CONF"

cat >> "$SQUID_CONF" <<'EOF'

# Load balancing across modems using random ACLs
EOF

# Generate ACLs and tcp_outgoing_address for load balancing
NUM_MODEMS=${#WWAN_IPS[@]}

if [ $NUM_MODEMS -eq 1 ]; then
    # Only one modem - use it directly
    echo "tcp_outgoing_address ${WWAN_IPS[0]}" >> "$SQUID_CONF"
elif [ $NUM_MODEMS -eq 2 ]; then
    # Two modems - 50/50 split
    cat >> "$SQUID_CONF" <<EOF
acl modem_select random 1/2
tcp_outgoing_address ${WWAN_IPS[0]} modem_select
tcp_outgoing_address ${WWAN_IPS[1]} !modem_select
EOF
else
    # Multiple modems - use hash-based distribution
    for i in "${!WWAN_IPS[@]}"; do
        PROB=$((i + 1))
        TOTAL=$NUM_MODEMS
        echo "acl modem_${i} random ${PROB}/${TOTAL}" >> "$SQUID_CONF"
        if [ $i -eq 0 ]; then
            echo "tcp_outgoing_address ${WWAN_IPS[$i]} modem_${i}" >> "$SQUID_CONF"
        elif [ $i -eq $((NUM_MODEMS - 1)) ]; then
            # Last modem gets everything else
            CONDITIONS=""
            for j in $(seq 0 $((i - 1))); do
                CONDITIONS="$CONDITIONS !modem_${j}"
            done
            echo "tcp_outgoing_address ${WWAN_IPS[$i]} $CONDITIONS" >> "$SQUID_CONF"
        else
            CONDITIONS="!modem_0"
            for j in $(seq 1 $((i - 1))); do
                CONDITIONS="$CONDITIONS !modem_${j}"
            done
            echo "tcp_outgoing_address ${WWAN_IPS[$i]} modem_${i} $CONDITIONS" >> "$SQUID_CONF"
        fi
    done
fi

cat >> "$SQUID_CONF" <<'EOF'

# IPv4 only configuration
dns_v4_first on
dns_v6_first off

# Cache and logs
cache_dir ufs /var/spool/squid 100 16 256
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
cache_store_log none

# Performance tuning
maximum_object_size 4096 KB
cache_mem 256 MB

# Disable caching for dynamic content
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320

# DNS
dns_nameservers 8.8.8.8 8.8.4.4
EOF

echo ""
echo "Generated configuration:"
echo "  Listening on: 0.0.0.0:$SQUID_PORT"
echo "  Allowed network: $VPN_NETWORK"
echo "  Outgoing IPs (load balanced):"
for i in "${!WWAN_IPS[@]}"; do
    echo "    - ${WWAN_IFACES[$i]}: ${WWAN_IPS[$i]}"
done

# Test configuration
echo ""
echo "Testing Squid configuration..."
if squid -k parse 2>&1 | grep -q "ERROR"; then
    echo "ERROR: Squid configuration has errors!"
    squid -k parse
    exit 1
fi

# Restart Squid
echo "Restarting Squid..."
systemctl restart squid
systemctl enable squid

# Verify Squid is running
sleep 2
if systemctl is-active --quiet squid; then
    echo "✓ Squid is running"
    systemctl status squid --no-pager -l | head -15
else
    echo "ERROR: Squid failed to start!"
    systemctl status squid --no-pager -l
    exit 1
fi

echo ""
echo "=== Squid Setup Complete ==="
echo "Proxy address: http://$(hostname -I | awk '{print $1}'):$SQUID_PORT"
echo ""
echo "Test from VPN client:"
echo "  curl -x http://10.8.0.1:$SQUID_PORT http://ifconfig.me"
echo "  curl -x http://10.8.0.1:$SQUID_PORT http://ipinfo.io/ip"
