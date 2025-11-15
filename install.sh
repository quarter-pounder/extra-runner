#!/bin/bash
# Main installer - orchestrates OS and services installation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utils
source "${SCRIPT_DIR}/bootstrap/utils.sh"

log_info "Starting full installation (OS + Services)..."

# Install OS first
log_info "=== Phase 1: OS Installation and Configuration ==="
bash "${SCRIPT_DIR}/install-os.sh" || {
    log_error "OS installation failed"
    exit 1
}

# Install services
log_info ""
log_info "=== Phase 2: Services Installation ==="
bash "${SCRIPT_DIR}/install-services.sh" || {
    log_error "Services installation failed"
    exit 1
}

log_success "Full installation completed successfully!"

