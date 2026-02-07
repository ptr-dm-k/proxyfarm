#!/bin/bash
# ProxyFarm Installation Script
# Main entry point for all setup operations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Show main menu
show_menu() {
    clear
    cat << "EOF"
╔══════════════════════════════════════════════════╗
║          ProxyFarm Installation Menu             ║
╚══════════════════════════════════════════════════╝
EOF
    echo ""
    echo "Setup Components:"
    echo "  1) Install ALL (Full Setup)"
    echo "  2) Setup Squid Proxy"
    echo "  3) Setup Multipath Routing"
    echo "  4) Setup Routing Persistence (NetworkManager Dispatcher)"
    echo "  5) Setup Routing Persistence (Systemd Service)"
    echo "  6) Setup VPS Proxy Forwarding"
    echo ""
    echo "Management:"
    echo "  7) Check System Status"
    echo "  8) Reinstall/Repair Routing"
    echo "  9) Uninstall ProxyFarm"
    echo ""
    echo "  0) Exit"
    echo ""
}

# Check system requirements
check_requirements() {
    print_header "Checking System Requirements"

    local all_good=true

    # Check if root
    if [ "$EUID" -ne 0 ]; then
        log_error "Must run as root"
        all_good=false
    else
        log_success "Running as root"
    fi

    # Check required commands
    print_step "Checking required commands..."
    local required_cmds=(mmcli nmcli ip systemctl)

    for cmd in "${required_cmds[@]}"; do
        if command_exists "$cmd"; then
            log_success "$cmd found"
        else
            log_error "$cmd not found"
            all_good=false
        fi
    done

    # Check for modems
    print_step "Checking for modems..."
    local modem_count=$(count_modems)
    if [ "$modem_count" -ge 2 ]; then
        log_success "Found $modem_count modems"
    elif [ "$modem_count" -eq 1 ]; then
        log_warning "Found only 1 modem (2 recommended)"
    else
        log_error "No modems found"
        all_good=false
    fi

    echo ""
    if [ "$all_good" = false ]; then
        log_error "System requirements not met"
        return 1
    fi

    log_success "All requirements met"
    return 0
}

# Full installation
install_all() {
    print_header "Full ProxyFarm Installation"

    if ! check_requirements; then
        log_error "Requirements check failed. Please fix issues and try again."
        press_enter
        return 1
    fi

    log_info "This will install:"
    echo "  - Squid Proxy with VPN access"
    echo "  - Multipath routing through modems"
    echo "  - NetworkManager dispatcher for persistence"
    echo ""

    if ! confirm "Continue with full installation?" "y"; then
        log_info "Installation cancelled"
        press_enter
        return
    fi

    # Step 1: Squid
    print_step "Step 1/3: Setting up Squid Proxy..."
    if "$SETUP_DIR/squid.sh"; then
        log_success "Squid setup completed"
    else
        log_error "Squid setup failed"
        press_enter
        return 1
    fi

    sleep 2

    # Step 2: Routing
    print_step "Step 2/3: Setting up Multipath Routing..."
    if "$SETUP_DIR/routing.sh"; then
        log_success "Routing setup completed"
    else
        log_error "Routing setup failed"
        press_enter
        return 1
    fi

    sleep 2

    # Step 3: Dispatcher
    print_step "Step 3/3: Installing NetworkManager Dispatcher..."
    if "$SETUP_DIR/nm-dispatcher.sh"; then
        log_success "Dispatcher setup completed"
    else
        log_error "Dispatcher setup failed"
        press_enter
        return 1
    fi

    print_header "Installation Complete!"
    log_success "ProxyFarm has been installed successfully"
    echo ""
    echo "Next steps:"
    echo "  1. Test the proxy: curl ifconfig.me"
    echo "  2. Check system status: $SCRIPT_DIR/check.sh"
    echo "  3. View logs: journalctl -f | grep ProxyFarm"
    echo ""

    press_enter
}

# Setup individual components
setup_squid() {
    print_header "Setup Squid Proxy"
    "$SETUP_DIR/squid.sh"
    press_enter
}

setup_routing() {
    print_header "Setup Multipath Routing"
    "$SETUP_DIR/routing.sh"
    press_enter
}

setup_dispatcher() {
    print_header "Setup NetworkManager Dispatcher"
    "$SETUP_DIR/nm-dispatcher.sh"
    press_enter
}

setup_systemd() {
    print_header "Setup Systemd Service"
    "$SETUP_DIR/systemd-service.sh"
    press_enter
}

setup_vps() {
    print_header "Setup VPS Proxy Forwarding"
    log_warning "This script should be run on the VPS, not on Orange Pi"
    echo ""
    if confirm "Continue anyway?" "n"; then
        "$SETUP_DIR/vps.sh"
    fi
    press_enter
}

# Check system status
check_status() {
    "$SCRIPT_DIR/check.sh"
    press_enter
}

# Repair routing
repair_routing() {
    print_header "Reinstall/Repair Routing"
    log_info "This will:"
    echo "  1. Re-run routing setup"
    echo "  2. Reinstall dispatcher (if was installed)"
    echo "  3. Restart services"
    echo ""

    if ! confirm "Continue?" "y"; then
        return
    fi

    # Re-run routing
    print_step "Re-running routing setup..."
    "$SETUP_DIR/routing.sh"

    # Reinstall dispatcher if it exists
    if has_nm_dispatcher; then
        print_step "Reinstalling dispatcher..."
        "$SETUP_DIR/nm-dispatcher.sh"
    fi

    # Restart services
    print_step "Restarting services..."
    if service_exists squid; then
        systemctl restart squid
        log_success "Squid restarted"
    fi

    log_success "Routing repair completed"
    press_enter
}

# Uninstall
run_uninstall() {
    print_header "Uninstall ProxyFarm"
    log_warning "This will remove all ProxyFarm configurations"
    echo ""

    if confirm "Are you sure you want to uninstall?" "n"; then
        "$SCRIPT_DIR/uninstall.sh"
    else
        log_info "Uninstall cancelled"
    fi

    press_enter
}

# Main loop
main() {
    while true; do
        show_menu

        read -p "Select option [0-9]: " choice

        case $choice in
            1) install_all ;;
            2) setup_squid ;;
            3) setup_routing ;;
            4) setup_dispatcher ;;
            5) setup_systemd ;;
            6) setup_vps ;;
            7) check_status ;;
            8) repair_routing ;;
            9) run_uninstall ;;
            0)
                echo ""
                log_info "Exiting..."
                exit 0
                ;;
            *)
                log_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Entry point
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    echo "Usage: sudo $0"
    exit 1
fi

main
