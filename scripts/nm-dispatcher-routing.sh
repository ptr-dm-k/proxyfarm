#!/bin/bash
# NetworkManager dispatcher script to maintain multipath routing
# Place in: /etc/NetworkManager/dispatcher.d/99-modem-routing
# chmod +x /etc/NetworkManager/dispatcher.d/99-modem-routing

INTERFACE=$1
ACTION=$2

# Log to syslog
logger "NM-Dispatcher: $INTERFACE $ACTION - Checking modem routing"

# Only run on connection up/down events
if [[ "$ACTION" != "up" && "$ACTION" != "down" && "$ACTION" != "connectivity-change" ]]; then
    exit 0
fi

# Wait a bit for interfaces to stabilize
sleep 2

# Run the routing setup script
/root/repo/proxyfarm/scripts/setup_modem_routing.sh >> /var/log/modem_routing.log 2>&1

logger "NM-Dispatcher: Modem routing setup completed"
