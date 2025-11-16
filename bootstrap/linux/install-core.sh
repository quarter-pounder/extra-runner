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
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# Install essential packages
log_info "Installing essential packages..."
apt-get install -y -qq \
    curl \
    wget \
    git \
    openssh-server \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    jq \
    unzip \
    htop \
    vim \
    ufw \
    fail2ban

log_success "Core packages installed successfully"

