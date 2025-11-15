#!/bin/bash
# Install and configure Ubuntu OS (post-install cleanup and setup)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}/bootstrap"
LINUX_DIR="${BOOTSTRAP_DIR}/linux"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utils
source "${BOOTSTRAP_DIR}/utils.sh"

log_info "Starting Ubuntu OS installation and configuration..."

# Run Linux OS scripts in order
SCRIPTS=(
    "cleanup-laptop.sh"
    "setup-ubuntu.sh"
    "preflight.sh"
    "install-core.sh"
    "install-docker.sh"
    "optimize-docker.sh"
    "verify.sh"
    "security-hardening.sh"
)

# Note: cleanup-laptop.sh runs in investigate-only mode by default
# Set INVESTIGATE_ONLY=false to enable cleanup

for script in "${SCRIPTS[@]}"; do
    log_info "Running ${script}..."
    bash "${LINUX_DIR}/${script}" || {
        log_error "Failed to run ${script}"
        exit 1
    }
done

log_success "Ubuntu OS installation and configuration completed successfully!"

