#!/bin/bash
# Migration script: Squid → Python Proxy
# Stops Squid and starts Python proxy server

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/common.sh"

check_root

print_header "Migration: Squid → Python Proxy"

log_warning "This script will:"
echo "  1. Stop and disable Squid"
echo "  2. Install Python dependencies (venv + pyyaml)"
echo "  3. Setup config/proxy.yaml"
echo "  4. Start ProxyFarm Python proxy (port 3128)"
echo ""
log_info "Squid will NOT be uninstalled (can rollback)"
echo ""

if ! confirm "Continue with migration?" "y"; then
    log_info "Migration cancelled"
    exit 0
fi

echo ""

# Step 1: Stop Squid
print_step "Stopping Squid..."

if systemctl is-active --quiet squid; then
    systemctl stop squid
    log_success "Squid stopped"
else
    log_info "Squid already stopped"
fi

if systemctl is-enabled --quiet squid; then
    systemctl disable squid
    log_success "Squid disabled"
else
    log_info "Squid already disabled"
fi

# Step 2: Check Python
print_step "Checking Python installation..."

if ! command -v python3 &> /dev/null; then
    log_error "Python3 not found! Installing..."
    apt-get update
    apt-get install -y python3 python3-pip python3-venv
fi

PYTHON_VERSION=$(python3 --version)
log_success "Python installed: $PYTHON_VERSION"

# Step 3: Create venv
print_step "Setting up Python virtual environment..."

VENV_PATH="/root/proxyfarm-venv"

if [ -d "$VENV_PATH" ]; then
    log_info "Virtual environment already exists"
else
    python3 -m venv "$VENV_PATH"
    log_success "Created venv: $VENV_PATH"
fi

# Activate venv
source "$VENV_PATH/bin/activate"

# Install dependencies
log_info "Installing dependencies..."
pip install --upgrade pip
pip install -r "$REPO_ROOT/requirements-proxy.txt"

log_success "Dependencies installed"

# Step 4: Setup config
print_step "Setting up configuration..."

CONFIG_DIR="$REPO_ROOT/config"
CONFIG_FILE="$CONFIG_DIR/proxy.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file not found: $CONFIG_FILE"
    log_info "Please create config/proxy.yaml manually"
    exit 1
fi

log_success "Config found: $CONFIG_FILE"

# Check if config has default passwords
if grep -q "pass1\|pass2\|pass3" "$CONFIG_FILE"; then
    log_warning "Config contains default passwords!"
    echo ""
    echo "Please edit config/proxy.yaml and change passwords:"
    echo "  nano $CONFIG_FILE"
    echo ""

    if ! confirm "Have you updated passwords?" "n"; then
        log_warning "Please update passwords before continuing"
        exit 1
    fi
fi

# Step 5: Install systemd service
print_step "Installing systemd service..."

SERVICE_FILE="/etc/systemd/system/proxyfarm-proxy.service"

if [ -f "$SERVICE_FILE" ]; then
    systemctl stop proxyfarm-proxy 2>/dev/null || true
fi

cp "$REPO_ROOT/systemd/proxyfarm-proxy.service" "$SERVICE_FILE"
systemctl daemon-reload

log_success "Service installed: proxyfarm-proxy.service"

# Step 6: Start proxy
print_step "Starting Python proxy..."

systemctl enable proxyfarm-proxy
systemctl start proxyfarm-proxy

# Wait a bit for startup
sleep 2

if systemctl is-active --quiet proxyfarm-proxy; then
    log_success "ProxyFarm proxy is running!"
else
    log_error "Failed to start proxy. Check logs:"
    echo "  journalctl -u proxyfarm-proxy -n 50"
    exit 1
fi

# Step 7: Test
print_step "Testing proxy..."

# Get modems IPs for reference
WWAN0_IP=$(ip -4 addr show wwan0 2>/dev/null | grep inet | awk '{print $2}' | cut -d'/' -f1)
WWAN1_IP=$(ip -4 addr show wwan1 2>/dev/null | grep inet | awk '{print $2}' | cut -d'/' -f1)

if [ -n "$WWAN0_IP" ]; then
    log_info "wwan0: $WWAN0_IP"
fi

if [ -n "$WWAN1_IP" ]; then
    log_info "wwan1: $WWAN1_IP"
fi

echo ""
log_info "Testing HTTP request..."

# Try to get first user from config
FIRST_USER=$(grep -A 1 "users:" "$CONFIG_FILE" | tail -1 | sed 's/^[[:space:]]*//' | sed 's/:.*//')
FIRST_PASS=$(grep -A 2 "$FIRST_USER:" "$CONFIG_FILE" | grep password | sed 's/.*password:[[:space:]]*//' | tr -d '"' | tr -d "'")

if [ -n "$FIRST_USER" ] && [ -n "$FIRST_PASS" ]; then
    TEST_RESULT=$(curl -s -x "http://$FIRST_USER:$FIRST_PASS@localhost:3128" --max-time 5 http://ifconfig.me 2>&1)

    if [ $? -eq 0 ]; then
        log_success "Proxy test successful!"
        echo "  Outgoing IP: $TEST_RESULT"
    else
        log_warning "Proxy test failed: $TEST_RESULT"
        echo "  Check: journalctl -u proxyfarm-proxy -f"
    fi
else
    log_warning "Could not parse user credentials from config"
    echo "  Test manually: curl -x http://user:pass@localhost:3128 ifconfig.me"
fi

# Step 8: Summary
print_header "Migration Complete!"

echo "Status:"
systemctl status proxyfarm-proxy --no-pager -l | head -10

echo ""
echo "Next steps:"
echo "  1. Check logs: journalctl -u proxyfarm-proxy -f"
echo "  2. Test proxy: curl -x http://user:pass@localhost:3128 https://ifconfig.me"
echo "  3. Update VPS if needed (socat should still work)"
echo ""
echo "Rollback:"
echo "  systemctl stop proxyfarm-proxy"
echo "  systemctl start squid"
echo ""

log_success "Python proxy is running on port 3128"
echo ""
echo "Config file: $CONFIG_FILE"
echo "Reload config: systemctl reload proxyfarm-proxy"
echo "Or: kill -HUP \$(pgrep -f proxy_full.py)"
