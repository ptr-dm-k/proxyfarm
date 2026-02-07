#!/bin/bash
# Common functions for ProxyFarm scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SETUP_DIR="$SCRIPT_DIR/setup"
BACKUP_DIR="$SCRIPT_DIR/backup"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check required commands
check_dependencies() {
    local missing=()

    for cmd in "$@"; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing[*]}"
        log_info "Install them with: apt install -y ${missing[*]}"
        return 1
    fi

    return 0
}

# Create backup of a file
backup_file() {
    local file="$1"
    local backup_name="$2"

    if [ -f "$file" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_path="$BACKUP_DIR/${backup_name:-$(basename $file)}.${timestamp}"
        cp "$file" "$backup_path"
        log_info "Backup created: $backup_path"
    fi
}

# Check if service exists
service_exists() {
    systemctl list-unit-files | grep -q "^$1"
}

# Check if service is active
service_is_active() {
    systemctl is-active --quiet "$1"
}

# Safely stop and disable service
stop_service() {
    local service="$1"

    if service_exists "$service"; then
        if service_is_active "$service"; then
            log_info "Stopping $service..."
            systemctl stop "$service"
        fi

        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            log_info "Disabling $service..."
            systemctl disable "$service"
        fi
    fi
}

# Remove file or directory safely
safe_remove() {
    local path="$1"
    local backup_name="$2"

    if [ -e "$path" ]; then
        if [ -n "$backup_name" ]; then
            backup_file "$path" "$backup_name"
        fi
        rm -rf "$path"
        log_info "Removed: $path"
    fi
}

# Confirm action
confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -p "$prompt" response
    response=${response:-$default}

    [[ "$response" =~ ^[Yy] ]]
}

# Print section header
print_header() {
    echo ""
    echo "========================================"
    echo "  $1"
    echo "========================================"
    echo ""
}

# Print step
print_step() {
    echo -e "\n${BLUE}==>${NC} $1"
}

# Get modem interfaces
get_modem_interfaces() {
    ip link show | grep -E '^[0-9]+: wwan[0-9]' | awk -F': ' '{print $2}' | cut -d'@' -f1
}

# Count modems
count_modems() {
    mmcli -L 2>/dev/null | grep -c "Modem/" || echo "0"
}

# Check if multipath routing is configured
has_multipath_route() {
    ip route show default | grep -q "nexthop"
}

# Get WiFi connection name
get_wifi_connection() {
    nmcli -t -f NAME,TYPE connection show --active | grep wireless | head -1 | cut -d: -f1
}

# Check if dispatcher is installed
has_nm_dispatcher() {
    [ -f /etc/NetworkManager/dispatcher.d/99-modem-routing ]
}

# Check if routing service is installed
has_routing_service() {
    service_exists modem-routing.service
}

# Check if Squid is configured
has_squid_config() {
    [ -f /etc/squid/squid.conf ] && grep -q "ProxyFarm" /etc/squid/squid.conf 2>/dev/null
}

# Wait for user to press Enter
press_enter() {
    echo ""
    read -p "Press Enter to continue..."
}
