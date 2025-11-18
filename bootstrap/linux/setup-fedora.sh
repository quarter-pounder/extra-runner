#!/bin/bash
# Initial Fedora Server OS setup and configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${BOOTSTRAP_DIR}/utils.sh"

log_info "Setting up Fedora Server OS configuration..."

check_root

# Update system
log_info "Updating system packages..."
dnf update -y -q

# Configure timezone
log_info "Configuring timezone..."
if command_exists timedatectl; then
    timedatectl set-timezone UTC || log_warn "Failed to set timezone (may need manual configuration)"
fi

# Configure locale
log_info "Configuring locale..."
if ! localedef -f UTF-8 -i en_US en_US.UTF-8 2>/dev/null; then
    log_warn "Failed to generate locale (may already exist)"
fi
localectl set-locale LANG=en_US.UTF-8 || log_warn "Failed to set locale"

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

        # Add to wheel group (Fedora's sudo group)
        usermod -aG wheel "$NEW_USER"

        # Set up SSH directory
        mkdir -p "/home/$NEW_USER/.ssh"
        chmod 700 "/home/$NEW_USER/.ssh"

        # Copy SSH keys from root if they exist
        if [[ -f /root/.ssh/authorized_keys ]]; then
            CP_CMD=$(get_command_path cp || echo "cp")
            $CP_CMD /root/.ssh/authorized_keys "/home/$NEW_USER/.ssh/authorized_keys"
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
dnf install -y -q dnf-automatic
cat > /etc/dnf/automatic.conf <<'EOF'
[commands]
upgrade_type = security
random_sleep = 0
network_online_timeout = 60
download_updates = yes
apply_updates = yes

[emitters]
emit_via = stdio,email

[email]
email_from = root@localhost
email_to = root
email_host = localhost
EOF

systemctl enable --now dnf-automatic.timer
log_success "Automatic security updates configured"

# Disable unnecessary services
log_info "Disabling unnecessary services..."
systemctl disable bluetooth.service 2>/dev/null || true
systemctl disable ModemManager.service 2>/dev/null || true

# Configure swap (if not already configured)
SWAP_ACTIVE=false
if command_exists swapon; then
    if swapon --show >/dev/null 2>&1 && [[ -n "$(swapon --show 2>/dev/null)" ]]; then
        SWAP_ACTIVE=true
        log_info "Swap already active:"
        swapon --show 2>/dev/null || true
    fi
fi

# Check if swapfile already exists
if [[ -f /swapfile ]]; then
    SWAP_ACTIVE=true
    log_info "Swap file already exists: /swapfile"
fi

if [[ "$SWAP_ACTIVE" == "false" ]]; then
    log_info "Configuring swap..."
    SWAP_SIZE="${SWAP_SIZE:-2G}"

    # Convert swap size to bytes for fallocate/dd
    SWAP_BYTES=""
    if [[ "$SWAP_SIZE" =~ ^([0-9]+)G$ ]]; then
        SIZE_GB="${BASH_REMATCH[1]}"
        SWAP_BYTES=$((SIZE_GB * 1024 * 1024 * 1024))
    elif [[ "$SWAP_SIZE" =~ ^([0-9]+)M$ ]]; then
        SIZE_MB="${BASH_REMATCH[1]}"
        SWAP_BYTES=$((SIZE_MB * 1024 * 1024))
    else
        log_warn "Invalid swap size format: $SWAP_SIZE. Using 2G as default."
        SWAP_BYTES=$((2 * 1024 * 1024 * 1024))
    fi

    # Try fallocate first, fall back to dd if it fails
    if command_exists fallocate; then
        if fallocate -l "$SWAP_SIZE" /swapfile 2>/dev/null; then
            log_info "Created swap file using fallocate"
        else
            log_warn "fallocate failed, trying dd..."
            DD_CMD=$(get_command_path dd || echo "dd")
            $DD_CMD if=/dev/zero of=/swapfile bs=1M count=$((SWAP_BYTES / 1024 / 1024)) status=progress 2>/dev/null || {
                log_error "Failed to create swap file"
                exit 1
            }
        fi
    else
        log_info "fallocate not available, using dd..."
        DD_CMD=$(get_command_path dd || echo "dd")
        $DD_CMD if=/dev/zero of=/swapfile bs=1M count=$((SWAP_BYTES / 1024 / 1024)) status=progress 2>/dev/null || {
            log_error "Failed to create swap file"
            exit 1
        }
    fi

    chmod 600 /swapfile

    # Create swap filesystem
    if command_exists mkswap; then
        mkswap /swapfile || {
            log_error "Failed to format swap file"
            exit 1
        }
    else
        log_error "mkswap command not found"
        exit 1
    fi

    # Enable swap
    if command_exists swapon; then
        swapon /swapfile || {
            log_error "Failed to enable swap"
            exit 1
        }
    else
        log_error "swapon command not found"
        exit 1
    fi

    # Add to fstab if not already present
    if ! grep -q '/swapfile' /etc/fstab 2>/dev/null; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    log_success "Swap configured: $SWAP_SIZE"
else
    log_info "Swap already configured, skipping"
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

log_success "Fedora Server OS setup completed"

