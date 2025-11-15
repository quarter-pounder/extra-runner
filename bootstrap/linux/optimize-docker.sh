#!/bin/bash
# Optimize Docker for CI/CD workloads

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$SCRIPT_DIR/.." source "${SCRIPT_DIR}/utils.sh"source "${SCRIPT_DIR}/utils.sh" pwd)"
source "${BOOTSTRAP_DIR}/utils.sh"

log_info "Optimizing Docker for CI/CD workloads..."

check_root

# Create Docker daemon config directory
mkdir -p /etc/docker

# Backup existing daemon.json if it exists
if [[ -f /etc/docker/daemon.json ]]; then
    log_info "Backing up existing daemon.json..."
    cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%Y%m%d_%H%M%S)
fi

# Configure Docker daemon
log_info "Configuring Docker daemon..."
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-address-pools": [
    {
      "base": "172.17.0.0/16",
      "size": 24
    }
  ]
}
EOF

# Restart Docker to apply changes
log_info "Restarting Docker to apply optimizations..."
systemctl restart docker
wait_for_service docker

log_success "Docker optimizations applied successfully"

