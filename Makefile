.PHONY: help logs status start stop restart pull ps shell brightness-get brightness-set brightness-inc brightness-dec brightness-zero brightness-restore font-get font-set font-list font-size-inc font-size-dec lid-close-status lid-close-disable lid-close-restore

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

# =======================================
# Font Controls (host machine console)
# =======================================

VCONSOLE_CONF = /etc/vconsole.conf
FONT_DIR = /usr/share/kbd/consolefonts

font-get: ## Show current console font
	@if command -v localectl >/dev/null 2>&1; then \
		echo "Current console font configuration:"; \
		localectl status | grep -E "VC Keymap|X11 Layout" || true; \
		if [ -f "$(VCONSOLE_CONF)" ]; then \
			grep -E "^FONT=" $(VCONSOLE_CONF) || echo "  FONT not set (using default)"; \
		fi; \
	elif [ -f "$(VCONSOLE_CONF)" ]; then \
		echo "Current console font configuration:"; \
		grep -E "^FONT=" $(VCONSOLE_CONF) || echo "  FONT not set (using default)"; \
		grep -E "^FONT_MAP=" $(VCONSOLE_CONF) || echo "  FONT_MAP not set"; \
		grep -E "^FONT_UNIMAP=" $(VCONSOLE_CONF) || echo "  FONT_UNIMAP not set"; \
	else \
		echo "No vconsole.conf found. Using system defaults."; \
	fi
	@if command -v setfont >/dev/null 2>&1; then \
		echo ""; \
		echo "Currently active font:"; \
		setfont 2>&1 | head -1 || echo "  Unable to determine active font"; \
	fi

font-set: ## Set console font (usage: make font-set FONT="lat9w-16")
	@if [ -z "$(FONT)" ]; then \
		echo "Usage: make font-set FONT=<font-name>"; \
		echo "Example: make font-set FONT=lat9w-16"; \
		echo "Use 'make font-list' to see available fonts"; \
		exit 1; \
	fi
	@FONT_FOUND=false; \
	if [ -d "$(FONT_DIR)" ]; then \
		if [ -f "$(FONT_DIR)/$(FONT).psf.gz" ] || [ -f "$(FONT_DIR)/$(FONT).psf" ]; then \
			FONT_FOUND=true; \
		fi; \
	fi; \
	if [ "$$FONT_FOUND" = "false" ] && [ -d "$(FONT_DIR)" ]; then \
		echo "Font '$(FONT)' not found in $(FONT_DIR)"; \
		echo "Use 'make font-list' to see available fonts"; \
		exit 1; \
	elif [ "$$FONT_FOUND" = "false" ] && [ ! -d "$(FONT_DIR)" ]; then \
		echo "Warning: Font directory $(FONT_DIR) not found."; \
		echo "Font will be set in config, but may not work until 'kbd' package is installed."; \
		echo "Install fonts: sudo dnf install kbd"; \
	fi
	@if [ ! -f "$(VCONSOLE_CONF)" ]; then \
		sudo touch $(VCONSOLE_CONF); \
	fi
	@if grep -q "^FONT=" $(VCONSOLE_CONF) 2>/dev/null; then \
		sudo sed -i "s|^FONT=.*|FONT=$(FONT)|" $(VCONSOLE_CONF); \
	else \
		echo "FONT=$(FONT)" | sudo tee -a $(VCONSOLE_CONF) >/dev/null; \
	fi
	@if command -v setfont >/dev/null 2>&1; then \
		sudo setfont $(FONT) 2>/dev/null || echo "Warning: Could not set font immediately (may require reboot or 'kbd' package)"; \
	fi
	@echo "Font set to $(FONT). Changes persist across reboots."

font-list: ## List available console fonts
	@if [ -d "$(FONT_DIR)" ]; then \
		echo "Available console fonts:"; \
		ls -1 $(FONT_DIR)/*.psf.gz $(FONT_DIR)/*.psf 2>/dev/null | \
			sed 's|$(FONT_DIR)/||;s|\.psf\.gz$$||;s|\.psf$$||' | \
			sort -u | \
			awk '{printf "  %s\n", $$1}'; \
	else \
		echo "Font directory $(FONT_DIR) not found."; \
		echo "Install console fonts: sudo dnf install kbd"; \
		echo ""; \
		echo "Common fonts (after installing kbd package):"; \
		echo "  lat9w-8, lat9w-14, lat9w-16, lat9w-18, lat9w-22"; \
		echo "  eurlatgr (your current font), ter-112n, ter-114n, ter-116n, ter-118n, ter-120n"; \
		echo "  sun12x22, sun8x16, UniCyr_8x16"; \
	fi

font-size-inc: ## Increase font size (switch to larger font)
	@CURRENT=$$(grep -E "^FONT=" $(VCONSOLE_CONF) 2>/dev/null | cut -d= -f2 | tr -d '"' || echo ""); \
	if [ -z "$$CURRENT" ]; then \
		echo "No font currently set. Use 'make font-set FONT=<name>' first."; \
		exit 1; \
	fi; \
	if echo "$$CURRENT" | grep -q "8$$"; then \
		NEW=$$(echo "$$CURRENT" | sed 's/8$$/14/'); \
	elif echo "$$CURRENT" | grep -q "14$$"; then \
		NEW=$$(echo "$$CURRENT" | sed 's/14$$/16/'); \
	elif echo "$$CURRENT" | grep -q "16$$"; then \
		NEW=$$(echo "$$CURRENT" | sed 's/16$$/18/'); \
	elif echo "$$CURRENT" | grep -q "18$$"; then \
		NEW=$$(echo "$$CURRENT" | sed 's/18$$/22/'); \
	elif echo "$$CURRENT" | grep -q "eurlatgr"; then \
		NEW="lat9w-16"; \
	else \
		echo "Current font '$$CURRENT' size not recognized. Use 'make font-set FONT=<name>' directly."; \
		exit 1; \
	fi; \
	if [ ! -d "$(FONT_DIR)" ] || [ -f "$(FONT_DIR)/$$NEW.psf.gz" ] || [ -f "$(FONT_DIR)/$$NEW.psf" ]; then \
		$(MAKE) --no-print-directory font-set FONT="$$NEW"; \
	else \
		echo "Larger font '$$NEW' not found. Current font: $$CURRENT"; \
		echo "Install fonts: sudo dnf install kbd"; \
		exit 1; \
	fi

font-size-dec: ## Decrease font size (switch to smaller font)
	@CURRENT=$$(grep -E "^FONT=" $(VCONSOLE_CONF) 2>/dev/null | cut -d= -f2 | tr -d '"' || echo ""); \
	if [ -z "$$CURRENT" ]; then \
		echo "No font currently set. Use 'make font-set FONT=<name>' first."; \
		exit 1; \
	fi; \
	if echo "$$CURRENT" | grep -q "22$$"; then \
		NEW=$$(echo "$$CURRENT" | sed 's/22$$/18/'); \
	elif echo "$$CURRENT" | grep -q "18$$"; then \
		NEW=$$(echo "$$CURRENT" | sed 's/18$$/16/'); \
	elif echo "$$CURRENT" | grep -q "16$$"; then \
		NEW=$$(echo "$$CURRENT" | sed 's/16$$/14/'); \
	elif echo "$$CURRENT" | grep -q "14$$"; then \
		NEW=$$(echo "$$CURRENT" | sed 's/14$$/8/'); \
	elif echo "$$CURRENT" | grep -q "eurlatgr"; then \
		NEW="lat9w-14"; \
	else \
		echo "Current font '$$CURRENT' size not recognized. Use 'make font-set FONT=<name>' directly."; \
		exit 1; \
	fi; \
	if [ ! -d "$(FONT_DIR)" ] || [ -f "$(FONT_DIR)/$$NEW.psf.gz" ] || [ -f "$(FONT_DIR)/$$NEW.psf" ]; then \
		$(MAKE) --no-print-directory font-set FONT="$$NEW"; \
	else \
		echo "Smaller font '$$NEW' not found. Current font: $$CURRENT"; \
		echo "Install fonts: sudo dnf install kbd"; \
		exit 1; \
	fi

# =======================================
# Lid Close Controls (host machine)
# =======================================

LOGIND_CONF = /etc/systemd/logind.conf
LOGIND_CONF_BACKUP = /etc/systemd/logind.conf.bak

lid-close-status: ## Show current lid close behavior
	@if [ -f "$(LOGIND_CONF)" ]; then \
		echo "Current lid close configuration:"; \
		grep -E "^HandleLidSwitch" $(LOGIND_CONF) || echo "  HandleLidSwitch not set (using default: suspend)"; \
		grep -E "^HandleLidSwitchExternalPower" $(LOGIND_CONF) || echo "  HandleLidSwitchExternalPower not set (using default: suspend)"; \
		grep -E "^HandleLidSwitchDocked" $(LOGIND_CONF) || echo "  HandleLidSwitchDocked not set (using default: suspend)"; \
	else \
		echo "logind.conf not found. Using system defaults (suspend on lid close)."; \
	fi

lid-close-disable: ## Prevent suspend when lid is closed
	@if [ ! -f "$(LOGIND_CONF)" ]; then \
		sudo touch $(LOGIND_CONF); \
	fi
	@if [ ! -f "$(LOGIND_CONF_BACKUP)" ]; then \
		sudo cp $(LOGIND_CONF) $(LOGIND_CONF_BACKUP); \
		echo "Backed up original logind.conf"; \
	fi
	@if grep -q "^HandleLidSwitch" $(LOGIND_CONF) 2>/dev/null; then \
		sudo sed -i 's/^HandleLidSwitch=.*/HandleLidSwitch=ignore/' $(LOGIND_CONF); \
	else \
		echo "HandleLidSwitch=ignore" | sudo tee -a $(LOGIND_CONF) >/dev/null; \
	fi
	@if grep -q "^HandleLidSwitchExternalPower" $(LOGIND_CONF) 2>/dev/null; then \
		sudo sed -i 's/^HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' $(LOGIND_CONF); \
	else \
		echo "HandleLidSwitchExternalPower=ignore" | sudo tee -a $(LOGIND_CONF) >/dev/null; \
	fi
	@if grep -q "^HandleLidSwitchDocked" $(LOGIND_CONF) 2>/dev/null; then \
		sudo sed -i 's/^HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' $(LOGIND_CONF); \
	else \
		echo "HandleLidSwitchDocked=ignore" | sudo tee -a $(LOGIND_CONF) >/dev/null; \
	fi
	@sudo systemctl restart systemd-logind || echo "Warning: Could not restart systemd-logind. Changes will take effect after reboot."
	@echo "Lid close suspend disabled. System will continue running when lid is closed."

lid-close-restore: ## Restore default behavior (suspend on lid close)
	@if [ -f "$(LOGIND_CONF_BACKUP)" ]; then \
		sudo cp $(LOGIND_CONF_BACKUP) $(LOGIND_CONF); \
		sudo systemctl restart systemd-logind || echo "Warning: Could not restart systemd-logind. Changes will take effect after reboot."; \
		echo "Restored original lid close behavior."; \
	else \
		if [ -f "$(LOGIND_CONF)" ]; then \
			sudo sed -i '/^HandleLidSwitch=/d' $(LOGIND_CONF); \
			sudo sed -i '/^HandleLidSwitchExternalPower=/d' $(LOGIND_CONF); \
			sudo sed -i '/^HandleLidSwitchDocked=/d' $(LOGIND_CONF); \
			sudo systemctl restart systemd-logind || echo "Warning: Could not restart systemd-logind. Changes will take effect after reboot."; \
			echo "Removed lid close overrides. Using system defaults (suspend on lid close)."; \
		else \
			echo "No configuration to restore. System already using defaults."; \
		fi; \
	fi
