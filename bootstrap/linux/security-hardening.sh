#!/bin/bash
# Security hardening: SSH and fail2ban

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${BOOTSTRAP_DIR}/utils.sh"

log_info "Applying security hardening..."

check_root

# SSH hardening
log_info "Hardening SSH configuration..."

SSH_CONFIG="/etc/ssh/sshd_config"
# Ensure OpenSSH Server is installed and config exists
if [[ ! -f "$SSH_CONFIG" ]]; then
    log_warn "SSH config not found at: $SSH_CONFIG. Installing openssh-server..."
    dnf install -y -q openssh-server || {
        error_exit "Failed to install openssh-server"
    }
    # Create minimal hardened sshd_config if still missing
    if [[ ! -f "$SSH_CONFIG" ]]; then
        log_info "Creating minimal SSH configuration at $SSH_CONFIG"
        cat > "$SSH_CONFIG" <<'EOF'
Port 22
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
AllowAgentForwarding no
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
    fi
fi

# Backup SSH config
if [[ -f "$SSH_CONFIG" ]]; then
    DATE_CMD=$(get_command_path date || echo "date")
    CP_CMD=$(get_command_path cp || echo "cp")
    $CP_CMD "$SSH_CONFIG" "${SSH_CONFIG}.bak.$($DATE_CMD +%Y%m%d_%H%M%S)"
fi

# Apply SSH hardening settings
log_info "Applying SSH security settings..."
sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG"
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_CONFIG"
sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/' "$SSH_CONFIG"
sed -i 's/#ClientAliveInterval.*/ClientAliveInterval 300/' "$SSH_CONFIG"
sed -i 's/#ClientAliveCountMax.*/ClientAliveCountMax 2/' "$SSH_CONFIG"

# Ensure these settings are set (add if not present)
if ! grep -q "^PermitRootLogin" "$SSH_CONFIG"; then
    echo "PermitRootLogin no" >> "$SSH_CONFIG"
fi
if ! grep -q "^PasswordAuthentication" "$SSH_CONFIG"; then
    echo "PasswordAuthentication no" >> "$SSH_CONFIG"
fi
if ! grep -q "^PubkeyAuthentication" "$SSH_CONFIG"; then
    echo "PubkeyAuthentication yes" >> "$SSH_CONFIG"
fi

# Determine SSH service name (Fedora uses 'sshd')
SSH_SERVICE="sshd"
if systemctl list-unit-files | grep -q "^ssh\\.service"; then
    SSH_SERVICE="ssh"
fi

log_warn "SSH password authentication disabled. Ensure SSH keys are configured before restarting SSH."
read -p "Continue with SSH restart? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl enable "$SSH_SERVICE" 2>/dev/null || true
    systemctl restart "$SSH_SERVICE"
    wait_for_service "$SSH_SERVICE"
    log_success "SSH service restarted with hardened configuration"
else
    log_warn "SSH restart skipped. Restart manually when ready: sudo systemctl restart $SSH_SERVICE"
fi

# fail2ban configuration
log_info "Configuring fail2ban..."

# Enable fail2ban
systemctl enable fail2ban
systemctl start fail2ban
wait_for_service fail2ban

# Create local jail configuration
FAIL2BAN_LOCAL="/etc/fail2ban/jail.local"
cat > "$FAIL2BAN_LOCAL" <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_)s

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 3
bantime = 7200
EOF

systemctl restart fail2ban
wait_for_service fail2ban

log_success "fail2ban configured and started"

# firewalld firewall (basic setup)
log_info "Configuring firewalld firewall..."

# Ensure firewalld is installed and running
systemctl enable firewalld
systemctl start firewalld
wait_for_service firewalld

# Allow SSH
firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || true

# Allow Node Exporter port (if monitoring is used)
firewall-cmd --permanent --add-port=9100/tcp >/dev/null 2>&1 || true

# Reload firewall
firewall-cmd --reload >/dev/null 2>&1 || true

log_success "firewalld firewall configured"

log_success "Security hardening completed"

