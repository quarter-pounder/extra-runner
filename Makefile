.PHONY: help logs status start stop restart pull ps shell

# Default runner directory
RUNNER_DIR ?= runner
COMPOSE_FILE = $(RUNNER_DIR)/docker-compose.yml

help: ## Show this help message
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# =======================================
# Runner specifics
# =======================================

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

# =======================================
# Brightness Controls (host machine)
# =======================================

BACKLIGHT ?= $(shell ls /sys/class/backlight | head -n1)
BR_DIR    = /sys/class/backlight/$(BACKLIGHT)

brightness-get: ## Show current brightness and max brightness
	@if [ -e "$(BR_DIR)/brightness" ]; then \
		echo "Backlight: $(BACKLIGHT)"; \
		echo -n "Current: "; cat $(BR_DIR)/brightness; \
		echo -n "Max:     "; cat $(BR_DIR)/max_brightness; \
	else \
		echo "No backlight interface found."; exit 1; \
	fi

brightness-set: ## Set brightness (usage: make brightness-set VAL=100)
	@if [ -z "$(VAL)" ]; then \
		echo "Usage: make brightness-set VAL=<number>"; exit 1; \
	fi
	@if [ -e "$(BR_DIR)/brightness" ]; then \
		echo "$(VAL)" | sudo tee $(BR_DIR)/brightness >/dev/null; \
		echo "Set brightness to $(VAL)."; \
	else \
		echo "No backlight interface found."; exit 1; \
	fi

brightness-inc: ## Increase brightness by DELTA (usage: make brightness-inc DELTA=50)
	@if [ -z "$(DELTA)" ]; then \
		echo "Usage: make brightness-inc DELTA=<number>"; exit 1; \
	fi
	@if [ -e "$(BR_DIR)/brightness" ]; then \
		B=$$(cat $(BR_DIR)/brightness); \
		N=$$((B + $(DELTA))); \
		echo $$N | sudo tee $(BR_DIR)/brightness >/dev/null; \
		echo "Brightness increased to $$N."; \
	else \
		echo "No backlight interface found."; exit 1; \
	fi

brightness-dec: ## Decrease brightness by DELTA (usage: make brightness-dec DELTA=50)
	@if [ -z "$(DELTA)" ]; then \
		echo "Usage: make brightness-dec DELTA=<number>"; exit 1; \
	fi
	@if [ -e "$(BR_DIR)/brightness" ]; then \
		B=$$(cat $(BR_DIR)/brightness); \
		N=$$((B - $(DELTA))); \
		echo $$N | sudo tee $(BR_DIR)/brightness >/dev/null; \
		echo "Brightness decreased to $$N."; \
	else \
		echo "No backlight interface found."; exit 1; \
	fi

BACKLIGHT := amdgpu_bl1

brightness-zero: ## Set brightness to 0 (panel appears off but safe)
	echo 0 | sudo tee /sys/class/backlight/$(BACKLIGHT)/brightness

brightness-restore: ## Restore brightness to readable level
	echo 20000 | sudo tee /sys/class/backlight/$(BACKLIGHT)/brightness
