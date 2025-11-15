# Bootstrap Scripts

Bootstrap scripts organized by category: Windows pre-install investigation, Linux OS setup, and service installation.

## Structure

```
bootstrap/
├── windows/          # Pre-install Windows investigation
│   └── trust-boundary.ps1
├── linux/           # Ubuntu OS installation and post-install cleanup
│   ├── cleanup-laptop.sh
│   ├── setup-ubuntu.sh
│   ├── preflight.sh
│   ├── install-core.sh
│   ├── install-docker.sh
│   ├── optimize-docker.sh
│   ├── verify.sh
│   └── security-hardening.sh
├── services/        # Service installation (runner, monitoring)
│   ├── setup-runner.sh
│   └── setup-node-exporter.sh
└── utils.sh         # Shared utility functions
```

## Usage

### Windows Investigation (Before Linux Installation)

Run on Windows to investigate OEM/recovery partitions and firmware:

```powershell
# As Administrator
.\bootstrap\windows\trust-boundary.ps1

# With cleanup (soft - disables WinRE, services, tasks)
.\bootstrap\windows\trust-boundary.ps1 -Cleanup
```

### Linux OS Installation

After installing Ubuntu, run:

```bash
sudo ./install-os.sh
```

This runs:
1. `cleanup-laptop.sh` - Investigate vendor-specific configurations (investigate-only by default)
2. `setup-ubuntu.sh` - Initial OS configuration
3. `preflight.sh` - System checks
4. `install-core.sh` - Core packages
5. `install-docker.sh` - Docker installation
6. `optimize-docker.sh` - Docker optimizations
7. `verify.sh` - Verification
8. `security-hardening.sh` - SSH/fail2ban hardening

### Services Installation

After OS is set up, install services:

```bash
export RUNNER_TOKEN="your_token"
export RUNNER_NAME="laptop-runner-01"
export RUNNER_ORG="your-org"  # or RUNNER_REPO="org/repo"
sudo ./install-services.sh
```

Or install everything at once:

```bash
sudo ./install.sh
```

## Script Details

### Windows Scripts

- **trust-boundary.ps1**: Investigates Windows OEM/recovery partitions, WinRE, EFI boot entries, BIOS settings, OEM services/tasks. Shows critical warnings if recovery triggers are detected.

### Linux OS Scripts

- **cleanup-laptop.sh**: Investigates vendor-specific configurations (kernels, applets, DNS, partitions, EFI, GRUB, Plymouth). Runs in investigate-only mode by default.
- **setup-ubuntu.sh**: Initial Ubuntu configuration (timezone, locale, user, security updates, swap)
- **preflight.sh**: System checks (architecture, OS version, connectivity)
- **install-core.sh**: Core system packages
- **install-docker.sh**: Docker installation
- **optimize-docker.sh**: Docker optimizations for CI/CD
- **verify.sh**: Verification checks
- **security-hardening.sh**: SSH and fail2ban configuration

### Service Scripts

- **setup-runner.sh**: GitHub Actions self-hosted runner setup
- **setup-node-exporter.sh**: Node Exporter for monitoring (optional)

