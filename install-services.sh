#!/bin/bash
# Install services (GitHub Actions runner, monitoring, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}/bootstrap"
SERVICES_DIR="${BOOTSTRAP_DIR}/services"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)" >&2
    exit 1
fi

# Source utils
source "${BOOTSTRAP_DIR}/utils.sh"

log_info "Starting services installation..."

# Auto-load environment variables from .env files if present
ENV_FILE="${SCRIPT_DIR}/.env"
RUNNER_ENV_FILE="${SCRIPT_DIR}/runner/.env"

load_env_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        log_info "Loading environment variables from ${file}"
        set -a
        # shellcheck disable=SC1090
        source "$file"
        set +a
        return 0
    fi
    return 1
}

# Prefer repo-level .env, fall back to runner/.env (for pre-created configs)
if ! load_env_file "$ENV_FILE"; then
    load_env_file "$RUNNER_ENV_FILE" || true
fi

# Check for required environment variables before runner setup
if [[ -z "${RUNNER_TOKEN:-}" ]]; then
    log_warn "RUNNER_TOKEN not set. Runner setup will be skipped."
    log_info "Set environment variables and run bootstrap/services/setup-runner.sh manually"
fi

# Setup runner if token is provided
if [[ -n "${RUNNER_TOKEN:-}" ]]; then
    log_info "Running setup-runner.sh..."
    bash "${SERVICES_DIR}/setup-runner.sh" || {
        log_error "Failed to setup runner"
        exit 1
    }
else
    log_warn "Skipping runner setup (RUNNER_TOKEN not set)"
    log_info "To setup runner later, run:"
    log_info "  export RUNNER_TOKEN=your_token"
    log_info "  export RUNNER_NAME=your_runner_name"
    log_info "  export RUNNER_ORG=your_org  # or RUNNER_REPO=org/repo"
    log_info "  sudo bash ${SERVICES_DIR}/setup-runner.sh"
fi

# Setup Node Exporter if requested
if [[ "${INSTALL_NODE_EXPORTER:-false}" == "true" ]]; then
    log_info "Running setup-node-exporter.sh..."
    bash "${SERVICES_DIR}/setup-node-exporter.sh" || {
        log_error "Failed to setup Node Exporter"
        exit 1
    }
else
    log_info "Node Exporter installation skipped (set INSTALL_NODE_EXPORTER=true to enable)"
fi

log_success "Services installation completed successfully!"
log_info ""
log_info "Next steps:"
if [[ -n "${RUNNER_TOKEN:-}" ]]; then
    log_info "  1. Verify runner is connected in GitHub UI"
    log_info "  2. Check runner logs: docker compose -f ${SCRIPT_DIR}/runner/docker-compose.yml logs -f"
fi
if [[ "${INSTALL_NODE_EXPORTER:-false}" == "true" ]]; then
    log_info "  3. Configure Prometheus to scrape Node Exporter at: http://$(hostname -I | awk '{print $1}'):9100/metrics"
fi

