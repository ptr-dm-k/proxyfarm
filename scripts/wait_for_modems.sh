#!/bin/bash
# Wait for modems to be ready before starting proxy

MAX_WAIT=60  # seconds
CHECK_INTERVAL=2  # seconds
WAITED=0

echo "Waiting for modems to initialize..."

while [ $WAITED -lt $MAX_WAIT ]; do
    # Check if any wwan interface has an IP
    WWAN_COUNT=$(ip -4 addr show | grep -c "inet.*wwan")

    if [ $WWAN_COUNT -gt 0 ]; then
        echo "Found $WWAN_COUNT modem(s) with IP address"

        # Show IPs
        ip -4 addr show | grep "inet.*wwan" | while read line; do
            echo "  $line"
        done

        exit 0
    fi

    echo "  No modems ready yet, waiting... ($WAITED/$MAX_WAIT seconds)"
    sleep $CHECK_INTERVAL
    WAITED=$((WAITED + CHECK_INTERVAL))
done

echo "WARNING: No modems found after $MAX_WAIT seconds"
echo "Starting proxy anyway - modems will be checked on each request"
exit 0  # Exit 0 to allow service to start anyway
