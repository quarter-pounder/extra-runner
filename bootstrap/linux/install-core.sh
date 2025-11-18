#!/bin/bash
# Install core system packages

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${BOOTSTRAP_DIR}/utils.sh"

log_info "Installing core system packages..."

check_root

# Update package lists
log_info "Updating package lists..."
dnf makecache -q

# Install essential packages
log_info "Installing essential packages..."
dnf install -y -q \
    curl \
    wget \
    git \
    openssh-server \
    ca-certificates \
    gnupg2 \
    jq \
    unzip \
    htop \
    vim \
    firewalld \
    fail2ban

log_success "Core packages installed successfully"
