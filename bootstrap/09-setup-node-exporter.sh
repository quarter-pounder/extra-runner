#!/bin/bash
# Setup Node Exporter for monitoring

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "Setting up Node Exporter for monitoring..."

check_root

# Check if Node Exporter should be installed
if [[ "${INSTALL_NODE_EXPORTER:-false}" != "true" ]]; then
    log_info "Node Exporter installation skipped (set INSTALL_NODE_EXPORTER=true to enable)"
    exit 0
fi

# Create node-exporter directory
RUNNER_DIR="$(cd "$(dirname "$SCRIPT_DIR")" && pwd)/runner"
mkdir -p "$RUNNER_DIR"

# Create docker-compose override for node-exporter
log_info "Creating Node Exporter configuration..."
cat > "$RUNNER_DIR/docker-compose.node-exporter.yml" <<'COMPOSE_EOF'
version: '3.8'

services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    ports:
      - "9100:9100"
    networks:
      - runner-net
COMPOSE_EOF

# Start Node Exporter
log_info "Starting Node Exporter..."
cd "$RUNNER_DIR"
docker compose -f docker-compose.yml -f docker-compose.node-exporter.yml pull node-exporter
docker compose -f docker-compose.yml -f docker-compose.node-exporter.yml up -d node-exporter

# Wait for Node Exporter to start
sleep 3

# Check Node Exporter status
if docker compose -f docker-compose.yml -f docker-compose.node-exporter.yml ps node-exporter | grep -q "Up"; then
    log_success "Node Exporter started successfully"
    log_info "Node Exporter metrics available at: http://localhost:9100/metrics"
    log_info "Configure Prometheus to scrape: http://$(hostname -I | awk '{print $1}'):9100/metrics"
else
    error_exit "Node Exporter failed to start. Check logs: docker compose -f $RUNNER_DIR/docker-compose.yml -f $RUNNER_DIR/docker-compose.node-exporter.yml logs node-exporter"
fi

