#!/bin/bash
# Install NetworkManager dispatcher script for persistent modem routing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCHER_DIR="/etc/NetworkManager/dispatcher.d"
DISPATCHER_SCRIPT="$DISPATCHER_DIR/99-modem-routing"

echo "=== Installing NetworkManager Dispatcher Script ==="

# Create dispatcher directory if it doesn't exist
if [ ! -d "$DISPATCHER_DIR" ]; then
    echo "Creating dispatcher directory: $DISPATCHER_DIR"
    mkdir -p "$DISPATCHER_DIR"
fi

# Copy the dispatcher script
echo "Installing dispatcher script: $DISPATCHER_SCRIPT"
cp "$SCRIPT_DIR/nm-dispatcher-routing.sh" "$DISPATCHER_SCRIPT"
chmod +x "$DISPATCHER_SCRIPT"

echo "Dispatcher script installed successfully"
echo ""
echo "The script will now automatically run whenever NetworkManager"
echo "brings up or changes network connections, maintaining your"
echo "modem routing configuration."
echo ""
echo "To test manually, run:"
echo "  $DISPATCHER_SCRIPT <interface> up"
echo ""
echo "To view logs:"
echo "  tail -f /var/log/modem_routing.log"
echo "  journalctl -f | grep NM-Dispatcher"
