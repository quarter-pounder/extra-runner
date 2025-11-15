#!/bin/bash
# Setup GitHub Actions runner

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "Setting up GitHub Actions runner..."

check_root

# Check required environment variables
if [[ -z "${RUNNER_TOKEN:-}" ]]; then
    error_exit "RUNNER_TOKEN environment variable is required"
fi

if [[ -z "${RUNNER_NAME:-}" ]]; then
    RUNNER_NAME="laptop-runner-$(hostname)"
    log_warn "RUNNER_NAME not set, using: $RUNNER_NAME"
fi

if [[ -z "${RUNNER_ORG:-}" ]] && [[ -z "${RUNNER_REPO:-}" ]]; then
    error_exit "Either RUNNER_ORG or RUNNER_REPO environment variable is required"
fi

# Set defaults
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,Linux,X64}"
DOCKER_ENABLED="${DOCKER_ENABLED:-true}"

log_info "Runner configuration:"
log_info "  Name: $RUNNER_NAME"
log_info "  Labels: $RUNNER_LABELS"
log_info "  Docker enabled: $DOCKER_ENABLED"
if [[ -n "${RUNNER_ORG:-}" ]]; then
    log_info "  Organization: $RUNNER_ORG"
else
    log_info "  Repository: $RUNNER_REPO"
fi

# Create runner directory
RUNNER_DIR="$(cd "$(dirname "$SCRIPT_DIR")" && pwd)/runner"
mkdir -p "$RUNNER_DIR"

# Create .env file for docker-compose
log_info "Creating runner environment file..."
cat > "$RUNNER_DIR/.env" <<EOF
RUNNER_NAME=$RUNNER_NAME
RUNNER_TOKEN=$RUNNER_TOKEN
RUNNER_LABELS=$RUNNER_LABELS
DOCKER_ENABLED=$DOCKER_ENABLED
EOF

if [[ -n "${RUNNER_ORG:-}" ]]; then
    echo "RUNNER_ORG=$RUNNER_ORG" >> "$RUNNER_DIR/.env"
else
    echo "RUNNER_REPO=$RUNNER_REPO" >> "$RUNNER_DIR/.env"
fi

# Copy docker-compose.yml if it doesn't exist
if [[ ! -f "$RUNNER_DIR/docker-compose.yml" ]]; then
    log_info "Creating docker-compose.yml..."
    cat > "$RUNNER_DIR/docker-compose.yml" <<'COMPOSE_EOF'
version: '3.8'

services:
  runner:
    image: myoung34/github-runner:latest
    container_name: github-runner
    restart: unless-stopped
    environment:
      - RUNNER_NAME=${RUNNER_NAME}
      - RUNNER_TOKEN=${RUNNER_TOKEN}
      - RUNNER_LABELS=${RUNNER_LABELS}
      - DOCKER_ENABLED=${DOCKER_ENABLED}
      - RUNNER_ORG=${RUNNER_ORG:-}
      - RUNNER_REPO=${RUNNER_REPO:-}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - runner-data:/home/runner
    env_file:
      - .env
    networks:
      - runner-net

volumes:
  runner-data:

networks:
  runner-net:
    driver: bridge
COMPOSE_EOF
fi

# Start runner
log_info "Starting GitHub Actions runner..."
cd "$RUNNER_DIR"
docker compose pull
docker compose up -d

# Wait for runner to start
sleep 5

# Check runner status
if docker compose ps | grep -q "Up"; then
    log_success "GitHub Actions runner started successfully"
    log_info "View logs with: docker compose -f $RUNNER_DIR/docker-compose.yml logs -f"
else
    error_exit "GitHub Actions runner failed to start. Check logs: docker compose -f $RUNNER_DIR/docker-compose.yml logs"
fi

