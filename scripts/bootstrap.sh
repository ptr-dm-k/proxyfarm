#!/bin/bash
set -e

# ProxyFarm initial system setup script
# Run as root: sudo ./bootstrap.sh

echo "=== ProxyFarm System Bootstrap ==="

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Step 1: System update${NC}"
apt-get update
apt-get upgrade -y

echo -e "${YELLOW}Step 2: Installing required packages${NC}"
apt-get install -y \
    modemmanager \
    network-manager \
    usb-modeswitch \
    libqmi-utils \
    libmbim-utils \
    iproute2 \
    iptables-persistent \
    openvpn \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    wget \
    git

echo -e "${YELLOW}Step 3: Configuring NetworkManager${NC}"
# Ensure NetworkManager manages all devices
cat > /etc/NetworkManager/conf.d/10-globally-managed-devices.conf << 'EOF'
[keyfile]
unmanaged-devices=none
EOF

systemctl restart NetworkManager

echo -e "${YELLOW}Step 4: Enabling services${NC}"
systemctl enable ModemManager
systemctl enable NetworkManager
systemctl start ModemManager
systemctl start NetworkManager

echo -e "${YELLOW}Step 5: Configuring sysctl${NC}"
cat > /etc/sysctl.d/99-proxyfarm.conf << 'EOF'
# IP forwarding
net.ipv4.ip_forward=1

# Multipath routing with L4 hash
net.ipv4.fib_multipath_hash_policy=1
EOF

sysctl -p /etc/sysctl.d/99-proxyfarm.conf

echo ""
echo -e "${GREEN}=== Bootstrap complete ===${NC}"
echo ""
echo "Next steps:"
echo "1. Configure OpenVPN (copy config to /etc/openvpn/client/)"
echo "2. Run ./install.sh to install ProxyFarm service"
echo "3. Edit /etc/proxyfarm/config.yaml"
echo "4. Start service: systemctl start proxyfarm"
echo ""
echo "To configure VPN:"
echo "  cp your-vpn.ovpn /etc/openvpn/client/proxyfarm.conf"
echo "  # Add to config: pull-filter ignore \"redirect-gateway\""
echo "  systemctl enable --now openvpn-client@proxyfarm"
