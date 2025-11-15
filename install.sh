#!/bin/bash
# One-liner installer for laptop runner bootstrap

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}/bootstrap"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utils
source "${BOOTSTRAP_DIR}/utils.sh"

log_info "Starting laptop runner bootstrap installation..."

# Check for required environment variables before runner setup
if [[ -z "${RUNNER_TOKEN:-}" ]]; then
    log_warn "RUNNER_TOKEN not set. Runner setup will be skipped."
    log_info "Set environment variables and run bootstrap/07-setup-runner.sh manually"
fi

# Run bootstrap scripts in order
SCRIPTS=(
    "00-cleanup-laptop.sh"
    "01-setup-ubuntu.sh"
    "02-preflight.sh"
    "03-install-core.sh"
    "04-install-docker.sh"
    "05-optimize-docker.sh"
    "06-verify.sh"
    "07-security-hardening.sh"
)

# Note: 00-cleanup-laptop.sh runs in investigate-only mode by default
# Set INVESTIGATE_ONLY=false to enable cleanup

for script in "${SCRIPTS[@]}"; do
    log_info "Running ${script}..."
    bash "${BOOTSTRAP_DIR}/${script}" || {
        log_error "Failed to run ${script}"
        exit 1
    }
done

# Setup runner if token is provided
if [[ -n "${RUNNER_TOKEN:-}" ]]; then
    log_info "Running 07-setup-runner.sh..."
    bash "${BOOTSTRAP_DIR}/07-setup-runner.sh" || {
        log_error "Failed to setup runner"
        exit 1
    }
else
    log_warn "Skipping runner setup (RUNNER_TOKEN not set)"
    log_info "To setup runner later, run:"
    log_info "  export RUNNER_TOKEN=your_token"
    log_info "  export RUNNER_NAME=your_runner_name"
    log_info "  export RUNNER_ORG=your_org  # or RUNNER_REPO=org/repo"
    log_info "  sudo bash ${BOOTSTRAP_DIR}/08-setup-runner.sh"
fi

# Setup Node Exporter if requested
if [[ "${INSTALL_NODE_EXPORTER:-false}" == "true" ]]; then
    log_info "Running 09-setup-node-exporter.sh..."
    bash "${BOOTSTRAP_DIR}/09-setup-node-exporter.sh" || {
        log_error "Failed to setup Node Exporter"
        exit 1
    }
else
    log_info "Node Exporter installation skipped (set INSTALL_NODE_EXPORTER=true to enable)"
fi

log_success "Bootstrap installation completed successfully!"
log_info ""
log_info "Next steps:"
log_info "  1. Verify runner is connected in GitHub UI"
log_info "  2. Check runner logs: docker compose -f ${SCRIPT_DIR}/runner/docker-compose.yml logs -f"
if [[ "${INSTALL_NODE_EXPORTER:-false}" == "true" ]]; then
    log_info "  3. Configure Prometheus to scrape Node Exporter at: http://$(hostname -I | awk '{print $1}'):9100/metrics"
fi

