#!/bin/bash
# Squid Proxy Setup for ProxyFarm

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

print_header "Squid Proxy Setup for LTE Modems"

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
log_info "Generating Squid configuration..."

# Backup existing config
backup_file "$SQUID_CONF" "squid.conf"

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

# Note: Load balancing is handled by kernel multipath routing
# configured by set_up_modems.sh script.
# Active modems with IPs: ${WWAN_IPS[@]}
# Squid will use default routing which automatically load balances.

cat >> "$SQUID_CONF" <<'EOF'

# Performance optimizations
# Connection timeouts (reduce delays)
connect_timeout 10 seconds
read_timeout 30 seconds
request_timeout 30 seconds
persistent_request_timeout 30 seconds

# File descriptor limits
max_filedescriptors 4096

# Disable unnecessary features for speed
forwarded_for off
via off

# Cache and logs
cache_dir ufs /var/spool/squid 100 16 256
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
cache_store_log none

# Performance tuning
maximum_object_size 4096 KB
cache_mem 256 MB
minimum_object_size 0 KB

# Disable caching for dynamic content
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320

# Fast DNS with Google DNS
dns_nameservers 8.8.8.8 8.8.4.4
positive_dns_ttl 6 hours
negative_dns_ttl 1 minute
fqdncache_size 2048

# Connection pooling for better performance
client_persistent_connections on
server_persistent_connections on
pconn_timeout 1 minute
half_closed_clients off
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

# Increase system limits for Squid
echo "Configuring system limits..."
mkdir -p /etc/systemd/system/squid.service.d
cat > /etc/systemd/system/squid.service.d/override.conf <<'LIMITEOF'
[Service]
LimitNOFILE=8192
LIMITEOF
systemctl daemon-reload

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
