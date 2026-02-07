#!/bin/bash
set -e

# ProxyFarm installation script
# Run as root: sudo ./install.sh

INSTALL_DIR="/opt/proxyfarm"
CONFIG_DIR="/etc/proxyfarm"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Installing ProxyFarm ==="

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

# Install Python dependencies
echo "Installing system dependencies..."
apt-get update
apt-get install -y python3 python3-pip python3-venv

# Create directories
echo "Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"

# Copy project files
echo "Copying files..."
cp -r "$PROJECT_DIR/src" "$INSTALL_DIR/"
cp "$PROJECT_DIR/requirements.txt" "$INSTALL_DIR/"
cp "$PROJECT_DIR/pyproject.toml" "$INSTALL_DIR/"

# Copy scripts
mkdir -p "$INSTALL_DIR/scripts"
cp "$PROJECT_DIR/scripts/"*.sh "$INSTALL_DIR/scripts/" 2>/dev/null || true
cp "$PROJECT_DIR/set_up_modems.sh" "$INSTALL_DIR/scripts/" 2>/dev/null || true
chmod +x "$INSTALL_DIR/scripts/"*.sh 2>/dev/null || true

# Create virtual environment
echo "Creating Python virtual environment..."
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"

# Install package
"$INSTALL_DIR/venv/bin/pip" install -e "$INSTALL_DIR"

# Copy config if not exists
if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
    echo "Creating default config..."
    cp "$PROJECT_DIR/config.example.yaml" "$CONFIG_DIR/config.yaml"
    echo ""
    echo "IMPORTANT: Edit $CONFIG_DIR/config.yaml and set your API key!"
    echo ""
fi

# Install systemd service
echo "Installing systemd service..."
cp "$PROJECT_DIR/systemd/proxyfarm.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable proxyfarm

echo ""
echo "=== Installation complete ==="
echo ""
echo "Configuration: $CONFIG_DIR/config.yaml"
echo "Logs: journalctl -u proxyfarm -f"
echo ""
echo "Commands:"
echo "  systemctl start proxyfarm    # Start service"
echo "  systemctl stop proxyfarm     # Stop service"
echo "  systemctl status proxyfarm   # Check status"
echo ""
echo "API will be available at: http://localhost:8080"
echo "Swagger docs: http://localhost:8080/docs"
