#!/bin/bash
# Setup VPS to forward proxy requests to Orange Pi through VPN

set -e

echo "=== Setting up proxy forwarding on VPS ==="
echo ""

ORANGE_PI_VPN_IP="10.8.0.2"
PROXY_PORT="3128"

# Check if running on VPS (Ubuntu)
if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
    echo "WARNING: This script is designed for Ubuntu. Proceeding anyway..."
fi

# Install socat if not present (lightweight port forwarder)
if ! command -v socat &> /dev/null; then
    echo "Installing socat..."
    apt-get update
    apt-get install -y socat
fi

# Create systemd service for socat proxy forwarding
echo "Creating systemd service..."
cat > /etc/systemd/system/proxy-forward.service <<EOF
[Unit]
Description=Proxy Forwarding to Orange Pi
After=network.target openvpn@orangepi.service
Wants=openvpn@orangepi.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/socat TCP4-LISTEN:${PROXY_PORT},fork,reuseaddr TCP4:${ORANGE_PI_VPN_IP}:${PROXY_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start service
echo "Starting proxy forwarding service..."
systemctl daemon-reload
systemctl enable proxy-forward
systemctl restart proxy-forward

# Wait a bit for service to start
sleep 2

# Check if service is running
if systemctl is-active --quiet proxy-forward; then
    echo "✓ Proxy forwarding service is running"
    systemctl status proxy-forward --no-pager | head -10
else
    echo "ERROR: Proxy forwarding service failed to start!"
    systemctl status proxy-forward --no-pager
    exit 1
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "VPS now forwards proxy requests to Orange Pi:"
echo "  External: curl -x http://138.2.138.243:${PROXY_PORT} http://ifconfig.me"
echo "  Or: curl -x http://\$(curl -s ifconfig.me):${PROXY_PORT} http://ifconfig.me"
echo ""
echo "Note: Make sure firewall allows incoming connections on port ${PROXY_PORT}"
