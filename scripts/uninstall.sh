#!/bin/bash
# ProxyFarm Uninstallation Script
# Removes all ProxyFarm configurations (except OpenVPN)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

check_root

print_header "ProxyFarm Uninstallation"

log_warning "This will remove:"
echo "  - Squid proxy configuration"
echo "  - Multipath routing configuration"
echo "  - NetworkManager dispatcher"
echo "  - Systemd routing service"
echo "  - ProxyFarm application (if installed)"
echo ""

log_info "This will PRESERVE:"
echo "  - OpenVPN configuration"
echo "  - Modem connections (gsm0, gsm1)"
echo "  - NetworkManager and ModemManager"
echo ""

if ! confirm "Are you sure you want to uninstall ProxyFarm?" "n"; then
    log_info "Uninstall cancelled"
    exit 0
fi

echo ""

# Create backup before uninstall
print_step "Creating backup..."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/uninstall_$TIMESTAMP"
mkdir -p "$BACKUP_PATH"

# Backup Squid config
if [ -f /etc/squid/squid.conf ]; then
    cp /etc/squid/squid.conf "$BACKUP_PATH/"
    log_info "Backed up: squid.conf"
fi

# Backup routing table
ip route show > "$BACKUP_PATH/routes.txt"
log_info "Backed up: routing table"

log_success "Backup created: $BACKUP_PATH"

# Stop and disable systemd services
print_step "Removing systemd services..."

# ProxyFarm application service
if service_exists proxyfarm.service; then
    stop_service proxyfarm.service
    safe_remove /etc/systemd/system/proxyfarm.service
    log_success "Removed proxyfarm.service"
fi

# Routing service and timer
if service_exists modem-routing.timer; then
    stop_service modem-routing.timer
    safe_remove /etc/systemd/system/modem-routing.timer
    log_success "Removed modem-routing.timer"
fi

if service_exists modem-routing.service; then
    stop_service modem-routing.service
    safe_remove /etc/systemd/system/modem-routing.service
    log_success "Removed modem-routing.service"
fi

# Reload systemd
if [ -n "$(ls /etc/systemd/system/*proxyfarm* 2>/dev/null)" ] || \
   [ -n "$(ls /etc/systemd/system/*modem-routing* 2>/dev/null)" ]; then
    systemctl daemon-reload
fi

# Remove NetworkManager dispatcher
print_step "Removing NetworkManager dispatcher..."
if [ -f /etc/NetworkManager/dispatcher.d/99-modem-routing ]; then
    safe_remove /etc/NetworkManager/dispatcher.d/99-modem-routing "nm-dispatcher"
    log_success "Removed dispatcher script"
fi

if [ -f "$SCRIPT_DIR/lib/nm-dispatcher-routing.sh" ]; then
    rm -f "$SCRIPT_DIR/lib/nm-dispatcher-routing.sh"
fi

# Restore default routing
print_step "Restoring default routing..."

# Remove multipath route if exists
if has_multipath_route; then
    ip route del default 2>/dev/null || true
    log_info "Removed multipath route"
fi

# Ensure WiFi has a default route
WIFI_CONN=$(get_wifi_connection)
if [ -n "$WIFI_CONN" ]; then
    # Get WiFi gateway
    WIFI_GW=$(ip route show | grep "wlan0" | grep -v default | awk '{print $1}' | head -1 | sed 's/\.[0-9]*\/.*/.1/')

    if [ -n "$WIFI_GW" ]; then
        ip route add default via "$WIFI_GW" dev wlan0 metric 600 2>/dev/null || true
        log_success "Restored WiFi default route"
    fi
fi

# Clean up Squid configuration
print_step "Cleaning Squid configuration..."

if service_exists squid; then
    # Stop Squid
    systemctl stop squid
    log_info "Stopped Squid"

    # Don't remove Squid entirely, just clean our config
    if [ -f /etc/squid/squid.conf ] && grep -q "ProxyFarm" /etc/squid/squid.conf; then
        # Remove ProxyFarm config, restore default
        if [ -f /etc/squid/squid.conf.dpkg-dist ]; then
            cp /etc/squid/squid.conf.dpkg-dist /etc/squid/squid.conf
            log_success "Restored default Squid config"
        else
            log_warning "Default Squid config not found, left as is"
        fi
    fi

    # Optionally ask if user wants to uninstall Squid entirely
    echo ""
    if confirm "Do you want to completely remove Squid?" "n"; then
        systemctl disable squid
        apt-get remove -y squid 2>/dev/null || true
        log_success "Removed Squid"
    else
        # Just restart with clean config
        systemctl start squid 2>/dev/null || true
        log_info "Squid left installed"
    fi
fi

# Clean up ProxyFarm application files
print_step "Cleaning application files..."

if [ -d /opt/proxyfarm ]; then
    if confirm "Remove ProxyFarm application from /opt/proxyfarm?" "y"; then
        rm -rf /opt/proxyfarm
        log_success "Removed /opt/proxyfarm"
    fi
fi

if [ -d /etc/proxyfarm ]; then
    if confirm "Remove ProxyFarm config from /etc/proxyfarm?" "y"; then
        rm -rf /etc/proxyfarm
        log_success "Removed /etc/proxyfarm"
    fi
fi

# Clean up logs
print_step "Cleaning logs..."
if [ -f /var/log/proxyfarm_routing.log ]; then
    rm -f /var/log/proxyfarm_routing.log
    log_info "Removed routing log"
fi

# Summary
print_header "Uninstallation Complete"

log_success "ProxyFarm has been uninstalled"
echo ""
log_info "Backup saved to: $BACKUP_PATH"
echo ""
log_info "Preserved:"
echo "  - OpenVPN configuration"
echo "  - Modem connections"
echo "  - NetworkManager and ModemManager"
echo ""

# Show final routing table
echo "Current routing table:"
ip route show | sed 's/^/  /'
echo ""

# Check current IP
echo -n "Current outgoing IP: "
curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "Unable to check"
echo ""

log_info "To restore ProxyFarm, run: $SCRIPT_DIR/install.sh"
echo ""
