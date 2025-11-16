#!/bin/bash
# Trust-boundary investigator for second-hand or OEM Linux laptops.
# Safely inspects kernels, modules, applets, services, DNS, partitions, EFI, udev rules, GRUB, Plymouth.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${BOOTSTRAP_DIR}/utils.sh"

log_info "Starting trust-boundary investigation..."

check_root

INVESTIGATE_ONLY="${INVESTIGATE_ONLY:-true}"
FINDINGS=()

################################################################################
# Safe helpers
################################################################################

safe_grep() { grep -E "$@" || true; }
safe_grep_i() { grep -iE "$@" || true; }

safe_find_exec() {
  find "$@" -type f -perm /111 -print0 2>/dev/null || true
}

################################################################################
# Kernel inspection
################################################################################

log_info "Checking installed kernels..."
INSTALLED_KERNELS=$(
  dpkg -l | awk '/^ii/ && $2 ~ /^linux-image/ {print $2}' | sort -V || true
)

VENDOR_KERNELS=$(echo "$INSTALLED_KERNELS" | safe_grep_i "vendor|oem|custom|manufacturer")

if [[ -n "${VENDOR_KERNELS}" ]]; then
    log_warn "Potential vendor kernels:"
    echo "$VENDOR_KERNELS"
    FINDINGS+=("vendor-kernels")
else
    log_info "No vendor kernels detected"
fi

################################################################################
# Kernel modules
################################################################################

log_info "Checking loaded kernel modules..."
VENDOR_MODULES=$(
  lsmod | awk '{print $1}' | safe_grep_i "vendor|oem|manufacturer|custom"
)

if [[ -n "${VENDOR_MODULES}" ]]; then
    log_warn "Potential vendor kernel modules:"
    echo "$VENDOR_MODULES"
    FINDINGS+=("vendor-modules")
fi

################################################################################
# Applets / utilities
################################################################################

log_info "Scanning for vendor applets..."
VENDOR_APPLETS=()

# Use process substitution to avoid subshell issue
while IFS= read -r -d $'\0' file; do
    bn="$(basename "$file")"
    if echo "$bn" | safe_grep_i "vendor|oem|manufacturer|brand|util|control"; then
        VENDOR_APPLETS+=("$file")
    fi
done < <(safe_find_exec /usr/bin /usr/local/bin /opt)

if (( ${#VENDOR_APPLETS[@]} > 0 )); then
    log_warn "Potential vendor applets:"
    printf '%s\n' "${VENDOR_APPLETS[@]}"
    FINDINGS+=("vendor-applets")
fi

################################################################################
# Systemd services
################################################################################

log_info "Checking systemd services..."
VENDOR_SERVICES=$(
  systemctl list-unit-files --type=service --all | safe_grep_i "vendor|oem|manufacturer|brand" | awk '{print $1}' || true
)

if [[ -n "$VENDOR_SERVICES" ]]; then
    log_warn "Potential vendor services:"
    echo "$VENDOR_SERVICES"
    FINDINGS+=("vendor-services")
fi

################################################################################
# DNS / resolv.conf
################################################################################

log_info "Checking DNS..."
if [[ -f /etc/resolv.conf ]]; then
    DNS_SERVERS=$(grep '^nameserver' /etc/resolv.conf | awk '{print $2}' || true)
    if [[ -n "$DNS_SERVERS" ]]; then
        log_info "DNS servers:"
        echo "$DNS_SERVERS"

        DNS_WHITELIST_REGEX="^(127\.0\.0\.1|127\.0\.0\.53|1\.1\.1\.1|8\.8\.8\.8|8\.8\.4\.4)$"
        SUSPICIOUS_DNS=$(echo "$DNS_SERVERS" | grep -Ev "$DNS_WHITELIST_REGEX" || true)

        if [[ -n "$SUSPICIOUS_DNS" ]]; then
            log_warn "Non-whitelisted DNS:"
            echo "$SUSPICIOUS_DNS"
            FINDINGS+=("dns-servers")
        fi
    fi
fi

if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    if command_exists resolvectl; then
        RESOLVED_DNS=$(resolvectl status 2>/dev/null | safe_grep "DNS Servers" | awk -F: '{print $2}')
    elif command_exists systemd-resolve; then
        RESOLVED_DNS=$(systemd-resolve --status 2>/dev/null | safe_grep "DNS Servers" | awk -F: '{print $2}')
    fi

    if [[ -n "${RESOLVED_DNS:-}" ]]; then
        log_info "systemd-resolved DNS: $RESOLVED_DNS"
    fi
fi

################################################################################
# /etc/hosts
################################################################################

log_info "Checking /etc/hosts..."
HOST_VENDOR=$(grep -Ev '^(#|$|127\.0\.0\.1|::1)' /etc/hosts | safe_grep_i "vendor|oem|manufacturer|telemetry")

if [[ -n "$HOST_VENDOR" ]]; then
    log_warn "Vendor-like /etc/hosts entries:"
    echo "$HOST_VENDOR"
    FINDINGS+=("vendor-hosts")
fi

################################################################################
# Partitions
################################################################################

log_info "Checking partitions..."
VENDOR_PARTITIONS=$(
  lsblk -o NAME,TYPE,LABEL,MOUNTPOINT | safe_grep_i "oem|vendor|recovery|factory|diag"
)

if [[ -n "$VENDOR_PARTITIONS" ]]; then
    log_warn "Potential vendor partitions:"
    echo "$VENDOR_PARTITIONS"
    FINDINGS+=("vendor-partitions")
fi

################################################################################
# fstab
################################################################################

log_info "Checking /etc/fstab..."
if [[ -f /etc/fstab ]]; then
    FSTAB_VENDOR=$(grep -vE '^(#|$)' /etc/fstab | safe_grep_i "vendor|oem|factory|recovery")
    if [[ -n "$FSTAB_VENDOR" ]]; then
        log_warn "Vendor-like entries in fstab:"
        echo "$FSTAB_VENDOR"
        FINDINGS+=("vendor-fstab")
    fi
fi

################################################################################
# udev rules
################################################################################

log_info "Checking udev rules..."
UDEV_VENDOR=$(
  find /etc/udev/rules.d /lib/udev/rules.d -name "*.rules" -print0 2>/dev/null |
    xargs -0 grep -Il -iE "vendor|oem|manufacturer|brand" 2>/dev/null || true
)

if [[ -n "$UDEV_VENDOR" ]]; then
    log_warn "Vendor-like udev rules:"
    echo "$UDEV_VENDOR"
    FINDINGS+=("vendor-udev")
fi

################################################################################
# GRUB
################################################################################

log_info "Inspecting GRUB config..."
if [[ -f /etc/default/grub ]]; then
    GRUB_VENDOR=$(safe_grep_i "vendor|oem|manufacturer|brand" /etc/default/grub)
    if [[ -n "$GRUB_VENDOR" ]]; then
        log_warn "Vendor-like GRUB settings:"
        echo "$GRUB_VENDOR"
        FINDINGS+=("vendor-grub")
    fi
fi

################################################################################
# Plymouth
################################################################################

if command_exists plymouth-set-default-theme; then
    log_info "Checking Plymouth theme..."
    theme=$(plymouth-set-default-theme 2>/dev/null | awk '{print $NF}' || true)
    if [[ -n "$theme" ]] && echo "$theme" | safe_grep_i "vendor|oem|manufacturer|brand"; then
        log_warn "Vendor-branded Plymouth theme: $theme"
        VENDOR_PLYMOUTH="$theme"
        FINDINGS+=("vendor-plymouth")
    fi
fi

################################################################################
# EFI / Bootloader
################################################################################

log_info "Checking EFI system partition..."
if [[ -d /sys/firmware/efi ]]; then
    EFI_MOUNT=$(findmnt -n -o TARGET /boot/efi 2>/dev/null || findmnt -n -o TARGET /boot 2>/dev/null || echo "")
    if [[ -n "$EFI_MOUNT" ]]; then
        log_info "EFI mounted at: $EFI_MOUNT"
        # Check for vendor-specific EFI entries (would need efibootmgr)
        if command_exists efibootmgr; then
            EFI_VENDOR=$(efibootmgr -v 2>/dev/null | safe_grep_i "vendor|oem|manufacturer|brand" || true)
            if [[ -n "$EFI_VENDOR" ]]; then
                log_warn "Potential vendor EFI boot entries found (review manually)"
                FINDINGS+=("vendor-efi")
            fi
        fi
    fi
fi

################################################################################
# SUMMARY
################################################################################

echo
log_info "======== Investigation Summary ========"
echo

if (( ${#FINDINGS[@]} == 0 )); then
    log_success "No obvious vendor artefacts detected"
    echo
else
    log_warn "${#FINDINGS[@]} vendor-like element categories found"
    echo
    log_info "Detailed findings:"
    echo

    # Detailed breakdown
    if [[ -n "${VENDOR_KERNELS:-}" ]]; then
        echo "  [KERNELS]"
        echo "$VENDOR_KERNELS" | sed 's/^/    - /'
        echo
    fi

    if [[ -n "${VENDOR_MODULES:-}" ]]; then
        echo "  [KERNEL MODULES]"
        echo "$VENDOR_MODULES" | sed 's/^/    - /'
        echo
    fi

    if (( ${#VENDOR_APPLETS[@]} > 0 )); then
        echo "  [APPLETS/UTILITIES]"
        printf '    - %s\n' "${VENDOR_APPLETS[@]}"
        echo
    fi

    if [[ -n "${VENDOR_SERVICES:-}" ]]; then
        echo "  [SYSTEMD SERVICES]"
        echo "$VENDOR_SERVICES" | sed 's/^/    - /'
        echo
    fi

    if [[ -n "${SUSPICIOUS_DNS:-}" ]]; then
        echo "  [DNS SERVERS]"
        echo "$SUSPICIOUS_DNS" | sed 's/^/    - /'
        echo
    fi

    if [[ -n "${HOST_VENDOR:-}" ]]; then
        echo "  [/etc/hosts ENTRIES]"
        echo "$HOST_VENDOR" | sed 's/^/    - /'
        echo
    fi

    if [[ -n "${VENDOR_PARTITIONS:-}" ]]; then
        echo "  [PARTITIONS]"
        echo "$VENDOR_PARTITIONS" | sed 's/^/    /'
        echo
    fi

    if [[ -n "${FSTAB_VENDOR:-}" ]]; then
        echo "  [/etc/fstab ENTRIES]"
        echo "$FSTAB_VENDOR" | sed 's/^/    - /'
        echo
    fi

    if [[ -n "${UDEV_VENDOR:-}" ]]; then
        echo "  [UDEV RULES]"
        echo "$UDEV_VENDOR" | sed 's/^/    - /'
        echo
    fi

    if [[ -n "${GRUB_VENDOR:-}" ]]; then
        echo "  [GRUB CONFIG]"
        echo "$GRUB_VENDOR" | sed 's/^/    - /'
        echo
    fi

    if [[ -n "${VENDOR_PLYMOUTH:-}" ]]; then
        echo "  [PLYMOUTH THEME]"
        echo "    - $VENDOR_PLYMOUTH"
        echo
    fi

    if [[ -n "${EFI_VENDOR:-}" ]]; then
        echo "  [EFI BOOT ENTRIES]"
        echo "$EFI_VENDOR" | sed 's/^/    - /'
        echo
    fi

    echo "  [CATEGORIES]"
    for f in "${FINDINGS[@]}"; do
        echo "    - $f"
    done
    echo
    log_info "Review the findings above before proceeding with cleanup."
    echo
fi

if [[ "$INVESTIGATE_ONLY" == "true" ]]; then
    log_info "Investigation mode only. No changes made."
    log_info "Set INVESTIGATE_ONLY=false to enable cleanup."
    exit 0
fi

################################################################################
# CLEANUP MODE (cautious)
################################################################################

echo
log_warn "=== Cleanup Mode Enabled ==="
read -p "Proceed with cleanup? (y/N): " ans
echo

if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    log_info "Cleanup aborted."
    exit 0
fi

################################################################################
# Remove applets
################################################################################

if (( ${#VENDOR_APPLETS[@]} > 0 )); then
    log_info "Removing vendor applets..."
    for file in "${VENDOR_APPLETS[@]}"; do
        log_info "Deleting $file"
        rm -f "$file" 2>/dev/null || true
    done
fi

################################################################################
# Disable services
################################################################################

if [[ -n "$VENDOR_SERVICES" ]]; then
    log_info "Disabling vendor services..."
    for svc in $VENDOR_SERVICES; do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
        log_info "Disabled $svc"
    done
fi

################################################################################
# GRUB cleanup
################################################################################

if [[ -f /etc/default/grub ]]; then
    log_info "Sanitizing GRUB..."
    # Use full path to date command for reliability
    if [[ -x /usr/bin/date ]]; then
        BACKUP_FILE="/etc/default/grub.bak.$(/usr/bin/date +%Y%m%d_%H%M%S)"
    elif [[ -x /bin/date ]]; then
        BACKUP_FILE="/etc/default/grub.bak.$(/bin/date +%Y%m%d_%H%M%S)"
    elif command_exists date; then
        BACKUP_FILE="/etc/default/grub.bak.$(date +%Y%m%d_%H%M%S)"
    else
        # Fallback: use epoch timestamp from file modification time
        BACKUP_FILE="/etc/default/grub.bak.$(stat -c %Y /etc/default/grub 2>/dev/null || echo 0)"
    fi
    cp /etc/default/grub "$BACKUP_FILE"

    # Remove quiet and splash from GRUB_CMDLINE_LINUX_DEFAULT, normalize spaces
    sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ {
        s/quiet//g
        s/splash//g
        s/  */ /g
        s/^\([^=]*="\) */\1/
        s/ *"$/"/
        s/=" *"$/=""/
    }' /etc/default/grub

    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub

    if command_exists update-grub; then
        update-grub >/dev/null 2>&1 || true
    fi
fi

################################################################################
# Plymouth
################################################################################

if [[ -n "${VENDOR_PLYMOUTH:-}" ]] && command_exists plymouth-set-default-theme; then
    log_info "Removing vendor Plymouth theme..."
    systemctl disable plymouth-quit-wait.service 2>/dev/null || true
    systemctl disable plymouth-read-write.service 2>/dev/null || true
    systemctl disable plymouth-start.service 2>/dev/null || true
    apt-get remove -y -qq plymouth 2>/dev/null || true
fi

################################################################################

log_success "Cleanup completed."
log_info "Review before reboot."
