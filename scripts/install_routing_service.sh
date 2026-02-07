#!/bin/bash
# Install systemd service for persistent modem routing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Installing Modem Routing Systemd Service ==="

# Copy service and timer files
echo "Installing service files..."
cp "$PROJECT_ROOT/systemd/modem-routing.service" /etc/systemd/system/
cp "$PROJECT_ROOT/systemd/modem-routing.timer" /etc/systemd/system/

# Reload systemd
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable and start the timer
echo "Enabling and starting modem-routing timer..."
systemctl enable modem-routing.timer
systemctl start modem-routing.timer

# Also run the service once immediately
echo "Running routing setup immediately..."
systemctl start modem-routing.service

echo ""
echo "=== Installation Complete ==="
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
