#!/bin/bash
# Security hardening: SSH and fail2ban

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$SCRIPT_DIR/.." source "${SCRIPT_DIR}/utils.sh"source "${SCRIPT_DIR}/utils.sh" pwd)"
source "${BOOTSTRAP_DIR}/utils.sh"

log_info "Applying security hardening..."

check_root

# SSH hardening
log_info "Hardening SSH configuration..."

SSH_CONFIG="/etc/ssh/sshd_config"
if [[ ! -f "$SSH_CONFIG" ]]; then
    error_exit "SSH config file not found: $SSH_CONFIG"
fi

# Backup SSH config
DATE_CMD=$(get_command_path date || echo "date")
CP_CMD=$(get_command_path cp || echo "cp")
$CP_CMD "$SSH_CONFIG" "${SSH_CONFIG}.bak.$($DATE_CMD +%Y%m%d_%H%M%S)"

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

log_warn "SSH password authentication disabled. Ensure SSH keys are configured before restarting SSH."
read -p "Continue with SSH restart? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl restart sshd
    wait_for_service sshd
    log_success "SSH service restarted with hardened configuration"
else
    log_warn "SSH restart skipped. Restart manually when ready: sudo systemctl restart sshd"
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

# UFW firewall (basic setup)
log_info "Configuring UFW firewall..."

# Allow SSH
ufw allow ssh >/dev/null 2>&1 || true

# Allow Node Exporter port (if monitoring is used)
ufw allow 9100/tcp comment 'Node Exporter' >/dev/null 2>&1 || true

# Enable UFW (non-interactive)
echo "y" | ufw enable >/dev/null 2>&1 || true

log_success "UFW firewall configured"

log_success "Security hardening completed"

