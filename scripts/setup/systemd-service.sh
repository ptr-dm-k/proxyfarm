#!/bin/bash
# Install systemd service and timer for persistent routing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

check_root

print_header "Installing Systemd Routing Service"

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Create service file
print_step "Creating modem-routing.service..."
cat > /etc/systemd/system/modem-routing.service << EOF
[Unit]
Description=ProxyFarm Modem Multipath Routing Setup
After=network-online.target ModemManager.service NetworkManager.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/setup/routing.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

# Restart routing if it fails
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create timer file
print_step "Creating modem-routing.timer..."
cat > /etc/systemd/system/modem-routing.timer << 'EOF'
[Unit]
Description=ProxyFarm Modem Routing Maintenance Timer
Requires=modem-routing.service

[Timer]
# Run on boot and every 5 minutes
OnBootSec=1min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

# Reload systemd
print_step "Reloading systemd daemon..."
systemctl daemon-reload

# Enable and start timer
print_step "Enabling and starting modem-routing timer..."
systemctl enable modem-routing.timer
systemctl start modem-routing.timer

# Run service once immediately
print_step "Running routing setup immediately..."
systemctl start modem-routing.service

log_success "Systemd Routing Service installed successfully"
echo ""
echo "The routing service will now:"
echo "  - Run at boot"
echo "  - Run every 5 minutes to maintain routing"
echo ""
echo "Commands:"
echo "  Status:  systemctl status modem-routing.timer"
echo "  Logs:    journalctl -u modem-routing.service -f"
echo "  Restart: systemctl restart modem-routing.service"
echo "  Stop:    systemctl stop modem-routing.timer"
echo ""
