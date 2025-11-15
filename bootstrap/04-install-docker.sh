#!/bin/bash
# Install Docker

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "Installing Docker..."

check_root

# Check if Docker is already installed
if command_exists docker && docker --version >/dev/null 2>&1; then
    log_warn "Docker is already installed: $(docker --version)"
    read -p "Continue with Docker installation? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping Docker installation"
        exit 0
    fi
fi

# Remove old versions
log_info "Removing old Docker versions..."
apt-get remove -y -qq docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker's official GPG key
log_info "Adding Docker GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up repository
log_info "Setting up Docker repository..."
ARCH=$(get_arch)
echo \
    "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
log_info "Installing Docker Engine..."
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
log_info "Starting Docker service..."
systemctl enable docker
systemctl start docker
wait_for_service docker

# Add current user to docker group (if not root)
if [[ -n "${SUDO_USER:-}" ]]; then
    log_info "Adding $SUDO_USER to docker group..."
    usermod -aG docker "$SUDO_USER"
    log_success "User $SUDO_USER added to docker group (logout/login required)"
fi

# Verify installation
if docker --version >/dev/null 2>&1; then
    log_success "Docker installed successfully: $(docker --version)"
else
    error_exit "Docker installation verification failed"
fi

