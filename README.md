# Extra-Runners

Bootstrap scripts for setting up a spare laptop as a dedicated GitHub Actions self-hosted runner on Ubuntu x86_64.

## Overview

This repository provides automated setup scripts to configure a spare laptop as a GitHub Actions runner with:
- Docker installation and optimization for CI/CD workloads
- GitHub Actions self-hosted runner (Docker-based)
- Security hardening (SSH, fail2ban)
- Optional Node Exporter for monitoring integration

## Quick Start

```bash
curl -fsSL https://repourl/main/install.sh | bash
```

Or clone and run locally:

```bash
git clone repo/extra-runners-bootstrap.git
cd extra-runners-bootstrap
sudo ./install.sh
```

## Prerequisites

- Ubuntu Server 24.04.3 LTS (noble), x86_64
- Root/sudo access
- GitHub personal access token or organization admin access
- Network connectivity

Note:
- Newer kernels in 24.04.x include better drivers for certain Realtek and MediaTek network adapters. Older Ubuntu releases may lack stable support for these devices, leading to missing NICs or unreliable connectivity during install/boot. Using 24.04.3 LTS mitigates these issues.

## Repository Structure

```
extra-runners/
├── bootstrap/
│   ├── windows/          # Pre-install Windows investigation
│   │   └── trust-boundary.ps1
│   ├── linux/           # Ubuntu OS installation and cleanup
│   │   ├── cleanup-laptop.sh
│   │   ├── setup-ubuntu.sh
│   │   ├── preflight.sh
│   │   ├── install-core.sh
│   │   ├── install-docker.sh
│   │   ├── optimize-docker.sh
│   │   ├── verify.sh
│   │   └── security-hardening.sh
│   ├── services/        # Service installation
│   │   ├── setup-runner.sh
│   │   └── setup-node-exporter.sh
│   └── utils.sh         # Shared utilities
├── install.sh           # Full installation (OS + Services)
├── install-os.sh        # OS installation only
├── install-services.sh  # Services installation only
└── runner/              # Runner configuration
```

## Setup Process

### Phase 1: Windows Investigation (Before Linux Installation)

On Windows, investigate OEM/recovery partitions and firmware:

```powershell
# As Administrator
.\bootstrap\windows\trust-boundary.ps1

# With cleanup (soft - disables WinRE, services, tasks)
.\bootstrap\windows\trust-boundary.ps1 -Cleanup
```

**Warning**: If critical findings are detected, the script will warn you NOT to install Linux yet. Follow the recommended steps (full disk wipe, BIOS settings, etc.) before proceeding.

### Phase 2: Linux OS Installation

After installing Ubuntu, run:

```bash
sudo ./install-os.sh
```

This runs:
1. **cleanup-laptop.sh** - Investigate vendor-specific configurations (investigate-only by default)
2. **setup-ubuntu.sh** - Initial Ubuntu OS configuration
3. **preflight.sh** - System checks (x86_64 architecture, Ubuntu version)
4. **install-core.sh** - Core system packages
5. **install-docker.sh** - Docker installation
6. **optimize-docker.sh** - Docker optimizations for CI/CD
7. **verify.sh** - Verification checks
8. **security-hardening.sh** - SSH and fail2ban configuration

### Phase 3: Services Installation

After OS is configured, install services:

```bash
export RUNNER_TOKEN="your_token"
export RUNNER_NAME="laptop-runner-01"
export RUNNER_ORG="your-org"  # or RUNNER_REPO="org/repo"
sudo ./install-services.sh
```

Or install everything at once:

```bash
sudo ./install.sh  # Runs install-os.sh then install-services.sh
```

## Configuration

### GitHub Actions Runner

Before running the setup, prepare:

1. **Runner Registration Token**: Get from GitHub repository or organization settings
   - Repository: Settings → Actions → Runners → New self-hosted runner
   - Organization: Settings → Actions → Runners → New runner

2. **Environment Variables**: Set in `runner/.env` or export before running:
   ```bash
   export RUNNER_NAME="laptop-runner-01"
   export RUNNER_TOKEN="runner_token_here"
   export RUNNER_ORG="org"  # For organization-level runner
   # OR for repository-level runner:
   export RUNNER_REPO="org/repo"  # Will be converted to REPO_URL automatically
   # OR use full URL:
   export REPO_URL="https://github.com/org/repo"
   export RUNNER_LABELS="self-hosted,Linux,X64"
   export DOCKER_ENABLED="true"
   ```

3. **Optional OS Setup Variables** (for 01-setup-ubuntu.sh):
   ```bash
   export HOSTNAME="laptop-runner"      # Set custom hostname
   export NEW_USER="runner"              # Create non-root user
   export SWAP_SIZE="4G"                 # Configure swap size
   ```

4. **Laptop Cleanup Investigation** (runs automatically, investigate-only by default):
   ```bash
   # Default: investigate-only mode (shows findings, no changes)
   # To enable cleanup after review:
   export INVESTIGATE_ONLY="false"       # Enable cleanup mode
   ```

### Runner Configuration

Edit `runner/docker-compose.yml` to customize:
- Runner name and labels
- Resource limits
- Volume mounts
- Network settings

## Manual Runner Setup

For a manual setup:

```bash
cd runner
cp .env.example .env
# Edit .env with configuration
docker-compose up -d
```

## Monitoring Integration

The optional Node Exporter setup allows integration with an external Prometheus instance:

1. Node Exporter runs on port 9100
2. Configure Prometheus to scrape: `http://laptop-ip:9100/metrics`
3. Firewall: Allow port 9100 from Prometheus server IP

## Security Notes

- SSH hardening disables password authentication (key-based only)
- fail2ban protects against brute force attacks
- Runner runs in isolated Docker container
- Review security settings in `06-security-hardening.sh`

## Troubleshooting

### Runner not connecting
- Verify RUNNER_TOKEN is valid and not expired
- Check network connectivity to GitHub
- Review runner logs: `docker-compose -f runner/docker-compose.yml logs`

### Docker issues
- Ensure Docker daemon is running: `sudo systemctl status docker`
- Check Docker socket permissions
- Verify user is in docker group

## Using Makefile

A Makefile is provided to simplify common runner operations:

```bash
# View logs (follow mode)
make logs

# Show runner status
make status

# Start/stop/restart runner
make start
make stop
make restart

# Pull latest image and restart
make update

# Open shell in runner container
make shell

# Execute command in container
make exec CMD="ls -la"

# Show all available commands
make help
```

## Multi-Runner Management

For managing multiple repository-based runners:

### Add a New Runner

```bash
# Using script
./scripts/add-runner.sh myproject-runner myorg/myrepo -t RUNNER_TOKEN

# Or with environment variables
export RUNNER_TOKEN=ghp_xxxxx
./scripts/add-runner.sh test-runner myorg/testrepo
```

### List All Runners

```bash
./scripts/list-runners.sh
```

### Remove a Runner

```bash
./scripts/remove-runner.sh myproject-runner
```

Runners are stored in `runners/<runner-name>/` directory, each with its own docker-compose.yml and .env file.

## Laptop Cleanup Investigation

The cleanup script runs automatically in **investigate-only mode** by default. It examines the system for:

- **Custom/vendor kernels** - Checks for manufacturer-specific kernel versions
- **Vendor applets** - Looks for vendor utilities and control panels
- **DNS configuration** - Identifies non-standard DNS servers
- **Vendor partitions** - Detects OEM/recovery/factory partitions
- **Boot configuration** - Checks GRUB and Plymouth for vendor branding
- **System services** - Identifies vendor-specific systemd services
- **Network settings** - Reviews /etc/hosts and udev rules

The script shows findings without making changes. To enable cleanup after review:

```bash
export INVESTIGATE_ONLY=false
sudo ./install.sh
```

Or run manually:

```bash
# Investigate only (default)
sudo bash bootstrap/00-cleanup-laptop.sh

# Enable cleanup mode
export INVESTIGATE_ONLY=false
sudo bash bootstrap/00-cleanup-laptop.sh
```

## Maintenance

### Update Runner
```bash
make update
# Or manually:
cd runner
docker-compose pull
docker-compose up -d
```

### View Logs
```bash
make logs
# Or manually:
docker-compose -f runner/docker-compose.yml logs -f
```

### Remove Runner
```bash
cd runner
docker-compose down
# Remove registration from GitHub UI
```

## Differences from pi-forge

This repository is simplified for single-purpose runner setup:
- No Pi-specific optimizations
- No config registry system
- No full monitoring stack
- No domain-based architecture
- Focused on x86_64 Ubuntu laptops

## License

MIT

