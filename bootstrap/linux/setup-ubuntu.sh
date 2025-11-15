#!/bin/bash
# Initial Ubuntu OS setup and configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$SCRIPT_DIR/.." source "${SCRIPT_DIR}/utils.sh"source "${SCRIPT_DIR}/utils.sh" pwd)"
source "${BOOTSTRAP_DIR}/utils.sh"

log_info "Setting up Ubuntu OS configuration..."

check_root

# Update system
log_info "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# Configure timezone (interactive prompt)
log_info "Configuring timezone..."
if command_exists timedatectl; then
    timedatectl set-timezone UTC || log_warn "Failed to set timezone (may need manual configuration)"
fi

# Configure locale
log_info "Configuring locale..."
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Set hostname if provided
if [[ -n "${HOSTNAME:-}" ]]; then
    log_info "Setting hostname to: $HOSTNAME"
    hostnamectl set-hostname "$HOSTNAME"
    echo "127.0.0.1 $HOSTNAME" >> /etc/hosts
fi

# Create non-root user if provided
if [[ -n "${NEW_USER:-}" ]]; then
    log_info "Creating user: $NEW_USER"
    if ! id "$NEW_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$NEW_USER"

        # Add to sudo group
        usermod -aG sudo "$NEW_USER"

        # Set up SSH directory
        mkdir -p "/home/$NEW_USER/.ssh"
        chmod 700 "/home/$NEW_USER/.ssh"

        # Copy SSH keys from root if they exist
        if [[ -f /root/.ssh/authorized_keys ]]; then
            cp /root/.ssh/authorized_keys "/home/$NEW_USER/.ssh/authorized_keys"
            chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
            chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
            log_success "SSH keys copied to $NEW_USER"
        fi

        log_success "User $NEW_USER created with sudo privileges"
    else
        log_warn "User $NEW_USER already exists"
    fi
fi

# Configure automatic security updates
log_info "Configuring automatic security updates..."
apt-get install -y -qq unattended-upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

# Enable automatic updates
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

log_success "Automatic security updates configured"

# Disable unnecessary services
log_info "Disabling unnecessary services..."
systemctl disable snapd.service snapd.socket 2>/dev/null || true
systemctl disable bluetooth.service 2>/dev/null || true
systemctl disable ModemManager.service 2>/dev/null || true

# Configure swap (if not already configured)
if [[ -z "$(swapon --show)" ]]; then
    log_info "Configuring swap..."
    SWAP_SIZE="${SWAP_SIZE:-2G}"
    fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log_success "Swap configured: $SWAP_SIZE"
fi

# Configure sysctl for better performance
log_info "Applying sysctl optimizations..."
cat >> /etc/sysctl.conf <<'EOF'

# Network optimizations
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# Docker optimizations
vm.max_map_count = 262144
fs.file-max = 2097152
EOF

sysctl -p >/dev/null 2>&1 || true

log_success "Ubuntu OS setup completed"

