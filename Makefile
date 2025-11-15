.PHONY: help logs status start stop restart pull ps shell

# Default runner directory
RUNNER_DIR ?= runner
COMPOSE_FILE = $(RUNNER_DIR)/docker-compose.yml

help: ## Show this help message
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

logs: ## Show runner logs (follow mode)
	docker compose -f $(COMPOSE_FILE) logs -f

logs-tail: ## Show last 100 lines of runner logs
	docker compose -f $(COMPOSE_FILE) logs --tail=100

status: ## Show runner status
	docker compose -f $(COMPOSE_FILE) ps

start: ## Start runner
	docker compose -f $(COMPOSE_FILE) up -d

stop: ## Stop runner
	docker compose -f $(COMPOSE_FILE) stop

restart: ## Restart runner
	docker compose -f $(COMPOSE_FILE) restart

down: ## Stop and remove runner container
	docker compose -f $(COMPOSE_FILE) down

pull: ## Pull latest runner image
	docker compose -f $(COMPOSE_FILE) pull

ps: ## List runner containers
	docker compose -f $(COMPOSE_FILE) ps

shell: ## Open shell in runner container
	docker compose -f $(COMPOSE_FILE) exec runner /bin/bash

exec: ## Execute command in runner container (usage: make exec CMD="ls -la")
	docker compose -f $(COMPOSE_FILE) exec runner $(CMD)

inspect: ## Inspect runner container
	docker compose -f $(COMPOSE_FILE) exec runner env

stats: ## Show container resource usage
	docker stats github-runner

clean: ## Remove runner container and volumes
	docker compose -f $(COMPOSE_FILE) down -v

update: pull restart ## Pull latest image and restart

# Multi-runner commands
list-runners: ## List all configured runners
	@ls -d runners/*/ 2>/dev/null | sed 's|runners/||;s|/||' || echo "No additional runners found"

# Node Exporter commands (if installed)
node-exporter-logs: ## Show Node Exporter logs
	docker compose -f $(COMPOSE_FILE) -f $(RUNNER_DIR)/docker-compose.node-exporter.yml logs -f node-exporter

node-exporter-status: ## Show Node Exporter status
	docker compose -f $(COMPOSE_FILE) -f $(RUNNER_DIR)/docker-compose.node-exporter.yml ps node-exporter

