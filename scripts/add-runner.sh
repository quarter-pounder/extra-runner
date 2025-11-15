#!/bin/bash
# Add a new repository-based runner

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNERS_DIR="$REPO_ROOT/runners"

# Source utils
source "$REPO_ROOT/bootstrap/utils.sh"

usage() {
    cat <<EOF
Usage: $0 <runner-name> <repo> [options]

Add a new repository-based GitHub Actions runner.

Arguments:
  runner-name    Unique name for this runner (e.g., myproject-runner)
  repo           Repository in format org/repo (e.g., myorg/myrepo)

Options:
  -t, --token TOKEN     Runner registration token (or set RUNNER_TOKEN env var)
  -l, --labels LABELS   Comma-separated labels (default: self-hosted,Linux,X64)
  -d, --disable-docker  Disable Docker support
  -h, --help           Show this help message

Examples:
  $0 myproject-runner myorg/myrepo -t ghp_xxxxx
  RUNNER_TOKEN=ghp_xxxxx $0 test-runner myorg/testrepo

EOF
}

# Parse arguments
RUNNER_NAME=""
REPO=""
RUNNER_TOKEN="${RUNNER_TOKEN:-}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,Linux,X64}"
DOCKER_ENABLED="true"

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--token)
            RUNNER_TOKEN="$2"
            shift 2
            ;;
        -l|--labels)
            RUNNER_LABELS="$2"
            shift 2
            ;;
        -d|--disable-docker)
            DOCKER_ENABLED="false"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [[ -z "$RUNNER_NAME" ]]; then
                RUNNER_NAME="$1"
            elif [[ -z "$REPO" ]]; then
                REPO="$1"
            else
                log_error "Too many arguments"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$RUNNER_NAME" ]] || [[ -z "$REPO" ]]; then
    log_error "Missing required arguments"
    usage
    exit 1
fi

if [[ -z "$RUNNER_TOKEN" ]]; then
    log_error "RUNNER_TOKEN is required (use -t/--token or set RUNNER_TOKEN env var)"
    exit 1
fi

# Validate repo format
if [[ ! "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
    log_error "Invalid repo format. Expected: org/repo, got: $REPO"
    exit 1
fi

# Create runners directory
mkdir -p "$RUNNERS_DIR"

# Check if runner already exists
RUNNER_DIR="$RUNNERS_DIR/$RUNNER_NAME"
if [[ -d "$RUNNER_DIR" ]]; then
    log_error "Runner '$RUNNER_NAME' already exists at $RUNNER_DIR"
    exit 1
fi

log_info "Creating new runner: $RUNNER_NAME for repo: $REPO"

# Create runner directory
mkdir -p "$RUNNER_DIR"

# Create .env file
log_info "Creating runner configuration..."
cat > "$RUNNER_DIR/.env" <<EOF
RUNNER_NAME=$RUNNER_NAME
RUNNER_TOKEN=$RUNNER_TOKEN
RUNNER_REPO=$REPO
RUNNER_LABELS=$RUNNER_LABELS
DOCKER_ENABLED=$DOCKER_ENABLED
EOF

# Create docker-compose.yml
log_info "Creating docker-compose.yml..."
cat > "$RUNNER_DIR/docker-compose.yml" <<'COMPOSE_EOF'
version: '3.8'

services:
  runner:
    image: myoung34/github-runner:latest
    container_name: github-runner-${RUNNER_NAME}
    restart: unless-stopped
    environment:
      - RUNNER_NAME=${RUNNER_NAME}
      - RUNNER_TOKEN=${RUNNER_TOKEN}
      - RUNNER_REPO=${RUNNER_REPO}
      - RUNNER_LABELS=${RUNNER_LABELS}
      - DOCKER_ENABLED=${DOCKER_ENABLED}
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

# Start runner
log_info "Starting runner..."
cd "$RUNNER_DIR"
docker compose pull
docker compose up -d

# Wait for runner to start
sleep 5

# Check status
if docker compose ps | grep -q "Up"; then
    log_success "Runner '$RUNNER_NAME' started successfully"
    log_info ""
    log_info "Runner directory: $RUNNER_DIR"
    log_info "View logs: docker compose -f $RUNNER_DIR/docker-compose.yml logs -f"
    log_info "Or use: make -C $REPO_ROOT logs RUNNER_DIR=$RUNNER_DIR"
    log_info ""
    log_info "To stop: docker compose -f $RUNNER_DIR/docker-compose.yml down"
    log_info "To remove: rm -rf $RUNNER_DIR"
else
    log_error "Runner failed to start. Check logs:"
    log_error "  docker compose -f $RUNNER_DIR/docker-compose.yml logs"
    exit 1
fi

