#!/bin/bash
# List all configured runners

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNERS_DIR="$REPO_ROOT/runners"
MAIN_RUNNER_DIR="$REPO_ROOT/runner"

source "$REPO_ROOT/bootstrap/utils.sh"

log_info "Listing all configured runners..."

# Check main runner
if [[ -f "$MAIN_RUNNER_DIR/docker-compose.yml" ]]; then
    echo ""
    echo "Main Runner:"
    echo "  Directory: $MAIN_RUNNER_DIR"
    if docker compose -f "$MAIN_RUNNER_DIR/docker-compose.yml" ps 2>/dev/null | grep -q "Up"; then
        echo "  Status: Running"
    else
        echo "  Status: Stopped"
    fi
    if [[ -f "$MAIN_RUNNER_DIR/.env" ]]; then
        RUNNER_NAME=$(grep "^RUNNER_NAME=" "$MAIN_RUNNER_DIR/.env" | cut -d= -f2)
        RUNNER_REPO=$(grep "^RUNNER_REPO=" "$MAIN_RUNNER_DIR/.env" | cut -d= -f2 2>/dev/null || echo "N/A")
        RUNNER_ORG=$(grep "^RUNNER_ORG=" "$MAIN_RUNNER_DIR/.env" | cut -d= -f2 2>/dev/null || echo "N/A")
        echo "  Name: $RUNNER_NAME"
        if [[ "$RUNNER_REPO" != "N/A" ]]; then
            echo "  Repo: $RUNNER_REPO"
        elif [[ "$RUNNER_ORG" != "N/A" ]]; then
            echo "  Org: $RUNNER_ORG"
        fi
    fi
fi

# Check additional runners
if [[ -d "$RUNNERS_DIR" ]] && [[ -n "$(ls -A "$RUNNERS_DIR" 2>/dev/null)" ]]; then
    echo ""
    echo "Additional Runners:"
    for runner_dir in "$RUNNERS_DIR"/*; do
        if [[ -d "$runner_dir" ]] && [[ -f "$runner_dir/docker-compose.yml" ]]; then
            runner_name=$(basename "$runner_dir")
            echo ""
            echo "  $runner_name:"
            echo "    Directory: $runner_dir"
            if docker compose -f "$runner_dir/docker-compose.yml" ps 2>/dev/null | grep -q "Up"; then
                echo "    Status: Running"
            else
                echo "    Status: Stopped"
            fi
            if [[ -f "$runner_dir/.env" ]]; then
                RUNNER_NAME=$(grep "^RUNNER_NAME=" "$runner_dir/.env" | cut -d= -f2)
                RUNNER_REPO=$(grep "^RUNNER_REPO=" "$runner_dir/.env" | cut -d= -f2 2>/dev/null || echo "N/A")
                echo "    Name: $RUNNER_NAME"
                if [[ "$RUNNER_REPO" != "N/A" ]]; then
                    echo "    Repo: $RUNNER_REPO"
                fi
            fi
        fi
    done
else
    echo ""
    echo "No additional runners found"
fi

echo ""

