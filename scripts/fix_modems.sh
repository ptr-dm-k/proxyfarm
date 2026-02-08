#!/bin/bash
# Fix modems connectivity and routing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

check_root

print_header "Fixing Modems and Routing"

# Step 1: Check modems status
print_step "Checking modems status..."

MODEM0_STATUS=$(mmcli -m 0 2>/dev/null | grep "state:" | awk -F': ' '{print $2}' | awk '{print $1}')
MODEM1_STATUS=$(mmcli -m 1 2>/dev/null | grep "state:" | awk -F': ' '{print $2}' | awk '{print $1}')

log_info "Modem 0 state: ${MODEM0_STATUS:-not found}"
log_info "Modem 1 state: ${MODEM1_STATUS:-not found}"

# Check for PIN lock
MODEM0_LOCK=$(mmcli -m 0 2>/dev/null | grep "lock:" | awk -F': ' '{print $2}')
MODEM1_LOCK=$(mmcli -m 1 2>/dev/null | grep "lock:" | awk -F': ' '{print $2}')

if [ -n "$MODEM0_LOCK" ] && [ "$MODEM0_LOCK" != "unknown" ] && [ "$MODEM0_LOCK" != "sim-pin2" ]; then
    log_error "Modem 0 is locked: $MODEM0_LOCK"
    log_info "This requires manual intervention"
fi

if [ -n "$MODEM1_LOCK" ] && [ "$MODEM1_LOCK" != "unknown" ] && [ "$MODEM1_LOCK" != "sim-pin2" ]; then
    log_error "Modem 1 is locked: $MODEM1_LOCK"
    log_info "This requires manual intervention"
fi

# SIM-PIN2 is usually OK, it's for special features, not basic connectivity
if [ "$MODEM0_LOCK" = "sim-pin2" ]; then
    log_warning "Modem 0 has sim-pin2 lock (this is usually OK for basic connectivity)"
fi

if [ "$MODEM1_LOCK" = "sim-pin2" ]; then
    log_warning "Modem 1 has sim-pin2 lock (this is usually OK for basic connectivity)"
fi

# Step 2: Try to connect both modems
print_step "Connecting modems..."

# Check if gsm0 connection exists
if nmcli connection show gsm0 &>/dev/null; then
    log_info "Found gsm0 connection"

    # Try to connect if not already connected
    if [ "$MODEM0_STATUS" != "connected" ]; then
        log_info "Connecting gsm0..."
        if nmcli connection up gsm0 2>&1; then
            log_success "gsm0 connected"
            sleep 5
        else
            log_error "Failed to connect gsm0"
            log_info "Trying to recreate connection..."

            # Get modem 0 device
            MODEM0_DEVICE=$(mmcli -m 0 2>/dev/null | grep "device:" | awk -F': ' '{print $2}' | tr -d ' ')

            if [ -n "$MODEM0_DEVICE" ]; then
                log_info "Creating new gsm0 connection for $MODEM0_DEVICE"
                nmcli connection delete gsm0 2>/dev/null
                nmcli connection add type gsm ifname "$MODEM0_DEVICE" con-name gsm0 apn internet
                sleep 2
                nmcli connection up gsm0
                sleep 5
            fi
        fi
    else
        log_success "gsm0 already connected"
    fi
else
    log_warning "gsm0 connection not found, creating..."

    # Try to find modem 0 device
    MODEM0_DEVICE=$(mmcli -m 0 2>/dev/null | grep "device:" | awk -F': ' '{print $2}' | tr -d ' ')

    if [ -n "$MODEM0_DEVICE" ]; then
        log_info "Creating gsm0 connection for $MODEM0_DEVICE"
        nmcli connection add type gsm ifname "$MODEM0_DEVICE" con-name gsm0 apn internet
        sleep 2
        nmcli connection up gsm0
        sleep 5
    else
        log_error "Could not find modem 0 device"
    fi
fi

# Check if gsm1 connection exists and is connected
if nmcli connection show gsm1 &>/dev/null; then
    log_info "Found gsm1 connection"

    if [ "$MODEM1_STATUS" != "connected" ]; then
        log_info "Connecting gsm1..."
        nmcli connection up gsm1 2>&1 || log_warning "gsm1 connection failed"
        sleep 5
    else
        log_success "gsm1 already connected"
    fi
else
    log_warning "gsm1 connection not found"
fi

# Step 3: Wait for connections to stabilize
log_info "Waiting for connections to stabilize..."
sleep 5

# Step 4: Check connection status
print_step "Checking connection status..."

nmcli connection show --active | grep -E "gsm|wwan"

# Get wwan interfaces
WWAN_INTERFACES=$(ip link show | grep -E '^[0-9]+: wwan[0-9]' | awk -F': ' '{print $2}' | cut -d'@' -f1)

if [ -z "$WWAN_INTERFACES" ]; then
    log_error "No wwan interfaces found!"
    echo ""
    echo "Debug info:"
    mmcli -L
    ip link show | grep -E "wwan|cdc"
    exit 1
fi

log_success "Found wwan interfaces:"
echo "$WWAN_INTERFACES" | while read iface; do
    IP=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+')
    if [ -n "$IP" ]; then
        echo "  $iface: $IP"
    else
        echo "  $iface: no IP"
    fi
done

# Count connected modems
CONNECTED_COUNT=$(echo "$WWAN_INTERFACES" | wc -l)
log_info "Connected modems: $CONNECTED_COUNT"

# Step 5: Setup routing
print_step "Setting up routing..."

if [ "$CONNECTED_COUNT" -eq 0 ]; then
    log_error "No modems connected, cannot setup routing"
    exit 1
elif [ "$CONNECTED_COUNT" -eq 1 ]; then
    log_warning "Only 1 modem connected, setting up single-path routing"
    "$SCRIPT_DIR/setup/routing.sh"
else
    log_success "Multiple modems connected, setting up multipath routing"
    "$SCRIPT_DIR/setup/routing.sh"
fi

# Step 6: Show final status
print_header "Final Status"

echo "Routing table:"
ip route show | grep default

echo ""
echo "Testing connectivity:"
curl -s --max-time 5 ifconfig.me || echo "Failed to get IP"

echo ""
log_success "Modem fix completed!"
echo ""
echo "If only one modem is working, check:"
echo "  1. SIM card is properly inserted"
echo "  2. SIM card has active data plan"
echo "  3. Modem hardware is working: mmcli -m 0 and mmcli -m 1"
echo ""
