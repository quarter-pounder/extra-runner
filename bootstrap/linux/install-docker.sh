#!/bin/bash
# Install Docker

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${BOOTSTRAP_DIR}/utils.sh"

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

# Remove old versions (ignore errors)
log_info "Removing old Docker versions (if any)..."
dnf remove -y -q docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

# Ensure prerequisites
log_info "Installing prerequisites..."
dnf install -y -q dnf-plugins-core

# Add Docker's official repository
log_info "Adding Docker repository..."
RELEASEVER=$(rpm -E %fedora)
BASEARCH=$(rpm -E %_arch)
cat > /etc/yum.repos.d/docker-ce.repo <<EOF
[docker-ce-stable]
name=Docker CE Stable - \$basearch
baseurl=https://download.docker.com/linux/fedora/${RELEASEVER}/\$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/fedora/gpg
EOF

# Install Docker Engine
log_info "Installing Docker Engine..."
set +e
dnf install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
DOCKER_INSTALL_RC=$?
set -e

# Fallback if Docker repo fails
if [[ $DOCKER_INSTALL_RC -ne 0 ]]; then
    log_warn "Docker CE packages unavailable. Trying Fedora's docker package..."
    set +e
    dnf install -y -q docker docker-compose
    DOCKER_FEDORA_RC=$?
    set -e
    if [[ $DOCKER_FEDORA_RC -ne 0 ]]; then
        log_warn "Fedora docker package failed. Using Docker convenience script..."
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh
    else
        log_success "Installed docker from Fedora repositories"
    fi
fi

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

