#!/bin/bash
# Utility functions for bootstrap scripts

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Error handling
error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root (use sudo)"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get full path to a command
get_command_path() {
    local cmd=$1
    if [[ -x "/usr/bin/$cmd" ]]; then
        echo "/usr/bin/$cmd"
    elif [[ -x "/bin/$cmd" ]]; then
        echo "/bin/$cmd"
    elif command_exists "$cmd"; then
        command -v "$cmd"
    else
        return 1
    fi
}

# Check if systemd service is active
service_is_active() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

# Check if systemd service is enabled
service_is_enabled() {
    systemctl is-enabled --quiet "$1" 2>/dev/null
}

# Wait for service to be active
wait_for_service() {
    local service=$1
    local timeout=${2:-30}
    local elapsed=0

    while ! service_is_active "$service"; do
        if [[ $elapsed -ge $timeout ]]; then
            error_exit "Service $service failed to start within ${timeout}s"
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    log_success "Service $service is active"
}

# Get Ubuntu version
get_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$VERSION_ID"
    else
        error_exit "Cannot determine Ubuntu version"
    fi
}

# Get architecture
get_arch() {
    uname -m
}

