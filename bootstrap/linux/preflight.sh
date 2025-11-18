#!/bin/bash
# Preflight checks for x86_64 Fedora Server system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${BOOTSTRAP_DIR}/utils.sh"

log_info "Running preflight checks..."

# Check root
check_root

# Check architecture
ARCH=$(get_arch)
if [[ "$ARCH" != "x86_64" ]]; then
    error_exit "Unsupported architecture: $ARCH. This setup is for x86_64 only."
fi
log_success "Architecture check passed: $ARCH"

# Check OS
if [[ ! -f /etc/os-release ]]; then
    error_exit "Cannot determine operating system"
fi

. /etc/os-release
if [[ "$ID" != "fedora" ]]; then
    error_exit "Unsupported OS: $ID. This setup is for Fedora Server only."
fi
log_success "OS check passed: $ID $VERSION_ID"

# Check Fedora version (43 recommended)
MAJOR=$(echo "$VERSION_ID" | cut -d. -f1)
if [[ -z "$MAJOR" ]]; then
    error_exit "Cannot parse Fedora version from VERSION_ID=$VERSION_ID"
fi
if [[ $MAJOR -lt 43 ]]; then
    error_exit "Fedora Server 43 or later required. Found: $VERSION_ID"
fi
if [[ $MAJOR -ne 43 ]]; then
    log_warn "Recommended: Fedora Server 43 (found $VERSION_ID)"
fi
log_success "Fedora version check passed: $VERSION_ID"

# Check internet connectivity
if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    error_exit "No internet connectivity detected"
fi
log_success "Internet connectivity check passed"

# Check disk space (at least 10GB free)
AVAILABLE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [[ $AVAILABLE_SPACE -lt 10 ]]; then
    log_warn "Low disk space: ${AVAILABLE_SPACE}GB available (recommended: 10GB+)"
else
    log_success "Disk space check passed: ${AVAILABLE_SPACE}GB available"
fi

# Check memory (at least 2GB)
TOTAL_MEM=$(free -g | awk '/^Mem:/ {print $2}')
if [[ $TOTAL_MEM -lt 2 ]]; then
    log_warn "Low memory: ${TOTAL_MEM}GB total (recommended: 2GB+)"
else
    log_success "Memory check passed: ${TOTAL_MEM}GB total"
fi

log_success "All preflight checks passed"

