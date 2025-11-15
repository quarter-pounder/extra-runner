#!/bin/bash
# Verification checks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$SCRIPT_DIR/.." source "${SCRIPT_DIR}/utils.sh"source "${SCRIPT_DIR}/utils.sh" pwd)"
source "${BOOTSTRAP_DIR}/utils.sh"

log_info "Running verification checks..."

# Verify Docker
if ! command_exists docker; then
    error_exit "Docker command not found"
fi

if ! service_is_active docker; then
    error_exit "Docker service is not active"
fi

if ! docker info >/dev/null 2>&1; then
    error_exit "Docker daemon is not accessible"
fi

log_success "Docker verification passed"

# Test Docker run
log_info "Testing Docker with hello-world..."
if docker run --rm hello-world >/dev/null 2>&1; then
    log_success "Docker test container ran successfully"
else
    error_exit "Docker test container failed"
fi

# Verify Docker Compose
if ! command_exists docker; then
    error_exit "Docker Compose plugin not found"
fi

if ! docker compose version >/dev/null 2>&1; then
    error_exit "Docker Compose plugin is not working"
fi

log_success "Docker Compose verification passed"

# Verify network connectivity
if ! ping -c 1 -W 2 github.com >/dev/null 2>&1; then
    log_warn "Cannot reach github.com (runner registration may fail)"
else
    log_success "Network connectivity to GitHub verified"
fi

log_success "All verification checks passed"

