#!/bin/bash
# Remove a runner

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNERS_DIR="$REPO_ROOT/runners"

source "$REPO_ROOT/bootstrap/utils.sh"

usage() {
    cat <<EOF
Usage: $0 <runner-name>

Remove a repository-based runner.

Arguments:
  runner-name    Name of the runner to remove

Options:
  -f, --force    Force removal without confirmation
  -h, --help     Show this help message

Examples:
  $0 myproject-runner
  $0 --force test-runner

EOF
}

FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=true
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
            RUNNER_NAME="$1"
            shift
            ;;
    esac
done

if [[ -z "${RUNNER_NAME:-}" ]]; then
    log_error "Missing runner name"
    usage
    exit 1
fi

RUNNER_DIR="$RUNNERS_DIR/$RUNNER_NAME"

if [[ ! -d "$RUNNER_DIR" ]]; then
    log_error "Runner '$RUNNER_NAME' not found at $RUNNER_DIR"
    exit 1
fi

if [[ "$FORCE" != "true" ]]; then
    log_warn "This will stop and remove runner: $RUNNER_NAME"
    log_warn "Directory: $RUNNER_DIR"
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        exit 0
    fi
fi

log_info "Stopping runner..."
cd "$RUNNER_DIR"
docker compose down -v 2>/dev/null || true

log_info "Removing runner directory..."
rm -rf "$RUNNER_DIR"

log_success "Runner '$RUNNER_NAME' removed successfully"
log_info "Remember to remove the runner registration from GitHub UI"

