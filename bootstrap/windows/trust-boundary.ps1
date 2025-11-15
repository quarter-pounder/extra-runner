<#
    Trust-boundary investigator for second-hand / OEM Windows laptops.

    Focus:
      - GPT / recovery / OEM partitions
      - WinRE (Windows Recovery Environment)
      - EFI / firmware boot entries (via BCD)
      - Lenovo / OEM BIOS flags (where available)
      - OEM services and scheduled tasks

    Default: investigation only (no changes).
    Optional: -Cleanup will offer to:
      - disable WinRE
      - disable OEM-like services and scheduled tasks
    It WILL NOT:
      - touch partitions
      - modify BCD entries
      - wipe disks
#>

[CmdletBinding()]
param(
    [switch]$Cleanup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
function Log-Info {
    param([string]$Message)
    Write-Host "[INFO ] $Message" -ForegroundColor Cyan
}

function Log-Success {
    param([string]$Message)
    Write-Host "[ OK  ] $Message" -ForegroundColor Green
}

function Log-Warn {
    param([string]$Message)
    Write-Host "[WARN ] $Message" -ForegroundColor Yellow
}

function Log-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# -----------------------------------------------------------------------------
# Admin check
# -----------------------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Log-Error "This script must be run as Administrator."
    exit 1
}

Log-Info "Starting Windows-side trust-boundary investigation..."

# Findings categories
$Findings = [System.Collections.Generic.List[string]]::new()

# For detailed sections
$PartitionFindings   = @()
$WinREInfo           = $null
$WinREEnabled        = $false
$FirmwareBootEntries = $null
$BiosSettingsRaw     = $null
$BiosSettingsHits    = @()
$OemServices         = @()
$OemTasks            = @()

# Simple OEM regex
$oemRegex = "Lenovo|OEM|OneKey|Recovery|Vantage|LSE|Service Engine|SupportAssist|Manufacturer"

# -----------------------------------------------------------------------------
# 1. GPT / partition analysis
# -----------------------------------------------------------------------------
Log-Info "Analyzing disk partitions (GPT, recovery, OEM)..."

try {
    $disks = Get-Disk
    $parts = $disks | Get-Partition | Sort-Object DiskNumber, PartitionNumber
} catch {
    Log-Error "Failed to query disk/partition information: $_"
    $parts = @()
}

if ($parts.Count -gt 0) {
    foreach ($p in $parts) {
        $info = [PSCustomObject]@{
            Disk        = $p.DiskNumber
            Part        = $p.PartitionNumber
            DriveLetter = $p.DriveLetter
            GptType     = $p.GptType
            SizeGB      = [math]::Round($p.Size / 1GB, 2)
            Type        = $p.Type
        }
        $PartitionFindings += $info
    }

    # Known "interesting" GPT type GUIDs (Windows-style)
    # Focus on OEM/Recovery partitions, not standard data partitions
    $interesting = $PartitionFindings | Where-Object {
        $_.GptType -match "DE94BBA4-06D1-4D40-A16A-BFD50179D6AC" -or # Windows RE
        $_.GptType -match "E3C9E316-0B5C-4DB8-817D-F92DF00215AE" -or # MSR (Microsoft Reserved)
        $_.Type    -match "OEM" -or
        $_.Type    -match "Recovery"
    }

    if ($interesting.Count -gt 0) {
        Log-Warn "Detected recovery/OEM-related or special partitions:"
        $interesting | Format-Table -AutoSize | Out-Host
        $Findings.Add("partitions")
    } else {
        Log-Info "No obvious recovery/OEM partitions detected."
    }
} else {
    Log-Warn "No partitions detected via Get-Partition (unusual)."
}

# -----------------------------------------------------------------------------
# 2. WinRE (Windows Recovery Environment)
# -----------------------------------------------------------------------------
Log-Info "Checking Windows Recovery Environment (WinRE)..."

try {
    $reagentOutput = & reagentc /info 2>&1
    $WinREInfo = $reagentOutput -join "`n"

    if ($WinREInfo -match "Windows RE status:\s+Enabled") {
        $WinREEnabled = $true
        Log-Warn "WinRE is ENABLED. This can participate in OS recovery / rollback."
        $Findings.Add("winre-enabled")
    } elseif ($WinREInfo -match "Windows RE status:\s+Disabled") {
        Log-Info "WinRE is disabled."
    } else {
        Log-Warn "Unable to clearly determine WinRE status from reagentc output."
    }
} catch {
    Log-Error "Failed to query WinRE state: $_"
}

# -----------------------------------------------------------------------------
# 3. EFI / firmware boot entries via BCD
# -----------------------------------------------------------------------------
Log-Info "Inspecting firmware-level boot entries (BCD / EFI)..."

$BootOrder = $null
try {
    $FirmwareBootEntries = & bcdedit /enum firmware 2>&1
    $FirmwareBootEntriesStr = $FirmwareBootEntries -join "`n"

    # Extract BootOrder if present
    if ($FirmwareBootEntriesStr -match "BootOrder\s+(.+)") {
        $BootOrder = $matches[1].Trim()
        Log-Info "Firmware BootOrder: $BootOrder"
    }

    if ($FirmwareBootEntriesStr -match "Windows Boot Manager") {
        Log-Warn "Windows Boot Manager present in firmware boot entries."
        $Findings.Add("firmware-windows-bootmgr")
    }

    if ($FirmwareBootEntriesStr -match "Recovery" -or $FirmwareBootEntriesStr -match "RamdiskOptions") {
        Log-Warn "Recovery-related firmware entries detected."
        $Findings.Add("firmware-recovery")
    }

    # Check if BootOrder contains multiple entries (potential recovery triggers)
    if ($BootOrder -and ($BootOrder -split '->').Count -gt 1) {
        Log-Warn "Multiple boot entries in BootOrder detected (may include recovery triggers)."
        $Findings.Add("firmware-bootorder-multiple")
    }
} catch {
    Log-Error "Failed to read firmware entries via bcdedit: $_"
}

# -----------------------------------------------------------------------------
# 4. Lenovo / OEM BIOS settings via WMI (best effort)
# -----------------------------------------------------------------------------
Log-Info "Checking for OEM/Lenovo BIOS settings (best effort)..."

$biosClasses = @(
    'Lenovo_BiosSettingEnhanced',
    'Lenovo_BiosSetting'
)

foreach ($cls in $biosClasses) {
    try {
        $BiosSettingsRaw = Get-CimInstance -Namespace root/WMI -ClassName $cls -ErrorAction Stop
        if ($BiosSettingsRaw) {
            Log-Info "Found BIOS settings class: $cls"

            $hits = $BiosSettingsRaw | Where-Object {
                $_.CurrentSetting -match "OS Optimized" -or
                $_.CurrentSetting -match "LSE" -or
                $_.CurrentSetting -match "Service Engine" -or
                $_.CurrentSetting -match "SecureBoot" -or
                $_.CurrentSetting -match "Recovery"
            }

            if ($hits.Count -gt 0) {
                $BiosSettingsHits += $hits
                Log-Warn "Potentially relevant BIOS settings detected (OEM / OS-optimized / LSE):"
                $hits | Select-Object CurrentSetting | Format-Table -AutoSize | Out-Host
                $Findings.Add("bios-oem-settings")
            }

            break
        }
    } catch {
        # Ignore if class not found or unsupported. This is OEM-specific.
    }
}

if (-not $BiosSettingsRaw) {
    Log-Info "No Lenovo/OEM-specific BIOS WMI classes found (or unsupported on this model)."
}

# -----------------------------------------------------------------------------
# 5. OEM services
# -----------------------------------------------------------------------------
Log-Info "Scanning for OEM / vendor services..."

try {
    $services = Get-Service
    $OemServices = $services | Where-Object {
        $_.Name        -match $oemRegex -or
        $_.DisplayName -match $oemRegex
    }
    if ($OemServices.Count -gt 0) {
        Log-Warn "OEM-like services detected:"
        $OemServices | Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize | Out-Host
        $Findings.Add("oem-services")
    } else {
        Log-Info "No obvious OEM-specific services detected."
    }
} catch {
    Log-Error "Failed to enumerate services: $_"
}

# -----------------------------------------------------------------------------
# 6. OEM scheduled tasks
# -----------------------------------------------------------------------------
Log-Info "Scanning for OEM / vendor scheduled tasks..."

try {
    $tasks = Get-ScheduledTask
    $OemTasks = $tasks | Where-Object {
        $_.TaskName -match $oemRegex -or
        $_.TaskPath -match $oemRegex
    }

    if ($OemTasks.Count -gt 0) {
        Log-Warn "OEM-like scheduled tasks detected:"
        $OemTasks | Select-Object TaskName, TaskPath, State | Format-Table -AutoSize | Out-Host
        $Findings.Add("oem-tasks")
    } else {
        Log-Info "No obvious OEM scheduled tasks detected."
    }
} catch {
    Log-Error "Failed to enumerate scheduled tasks: $_"
}

# -----------------------------------------------------------------------------
# 7. OEM Recovery Images (install.wim)
# -----------------------------------------------------------------------------
Log-Info "Checking for OEM recovery images..."

$OemRecoveryImage = $null
$recoveryPaths = @(
    "C:\Recovery\OEM\install.wim",
    "C:\Recovery\WindowsRE\winre.wim",
    "D:\Recovery\OEM\install.wim",
    "E:\Recovery\OEM\install.wim"
)

foreach ($path in $recoveryPaths) {
    if (Test-Path $path) {
        Log-Warn "Found recovery image: $path"
        $OemRecoveryImage = $path
        $Findings.Add("oem-recovery-image")

        try {
            Log-Info "Querying image info via DISM..."
            $dismOutput = & dism /Get-ImageInfo /ImageFile:$path 2>&1
            if ($LASTEXITCODE -eq 0) {
                $dismOutput | Out-Host
            } else {
                Log-Warn "DISM query failed or image may be corrupted."
            }
        } catch {
            Log-Error "Failed to query recovery image: $_"
        }
        break
    }
}

if (-not $OemRecoveryImage) {
    Log-Info "No OEM recovery images found in common locations."
}

# -----------------------------------------------------------------------------
# CRITICAL WARNING CHECK
# -----------------------------------------------------------------------------
$criticalFindings = @(
    "partitions",
    "winre-enabled",
    "firmware-windows-bootmgr",
    "firmware-recovery",
    "firmware-bootorder-multiple",
    "oem-recovery-image",
    "bios-oem-settings"
)

$hasCriticalFindings = $false
foreach ($finding in $criticalFindings) {
    if ($Findings -contains $finding) {
        $hasCriticalFindings = $true
        break
    }
}

# -----------------------------------------------------------------------------
# SUMMARY
# -----------------------------------------------------------------------------
Write-Host ""
Log-Info  "================ Investigation Summary ================"
Write-Host ""

if ($Findings.Count -eq 0) {
    Log-Success "No major OEM / recovery / firmware persistence indicators detected."
} else {
    Log-Warn "$($Findings.Count) finding categories detected:"
    $Findings | Sort-Object -Unique | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""
    Log-Info "Review detailed findings below before proceeding with cleanup."
}

# -----------------------------------------------------------------------------
# CRITICAL WARNING
# -----------------------------------------------------------------------------
if ($hasCriticalFindings) {
    Write-Host ""
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host "!!! DO NOT INSTALL LINUX YET !!!" -ForegroundColor Red -BackgroundColor Yellow
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host ""
    Log-Error "Machine contains OEM recovery triggers / firmware entries that can override the Linux installation."
    Write-Host ""
    Log-Warn "Recommended steps before Linux installation:"
    Write-Host "  1. Full disk wipe: sgdisk --zap-all /dev/sdX (from live USB)"
    Write-Host "  2. Disable WinRE: reagentc /disable (already done if cleanup ran)"
    Write-Host "  3. Disable BIOS vendor features (LSE, Service Engine, etc.)"
    Write-Host "  4. Remove OEM partitions during Linux installation"
    Write-Host "  5. Verify BootOrder after installation"
    Write-Host ""
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host ""
}

Write-Host ""

# Detail recap for human sanity
if ($PartitionFindings.Count -gt 0) {
    Write-Host "[DETAIL] Partitions (all detected):" -ForegroundColor Cyan
    $PartitionFindings | Format-Table -AutoSize | Out-Host
    Write-Host ""

    # Show interesting partitions separately if any
    $interesting = $PartitionFindings | Where-Object {
        $_.GptType -match "DE94BBA4-06D1-4D40-A16A-BFD50179D6AC" -or
        $_.GptType -match "E3C9E316-0B5C-4DB8-817D-F92DF00215AE" -or
        $_.Type    -match "OEM" -or
        $_.Type    -match "Recovery"
    }
    if ($interesting.Count -gt 0) {
        Write-Host "[DETAIL] Interesting partitions (OEM/Recovery/MSR):" -ForegroundColor Yellow
        $interesting | Format-Table -AutoSize | Out-Host
        Write-Host ""
    }
}

if ($WinREInfo) {
    Write-Host "[DETAIL] WinRE (reagentc /info):" -ForegroundColor Cyan
    $WinREInfo | Out-Host
    Write-Host ""
}

if ($FirmwareBootEntries) {
    Write-Host "[DETAIL] Firmware boot entries (bcdedit /enum firmware):" -ForegroundColor Cyan
    $FirmwareBootEntries | Out-Host
    Write-Host ""

    if ($BootOrder) {
        Write-Host "[DETAIL] BootOrder:" -ForegroundColor Cyan
        Write-Host "  BootOrder: $BootOrder" -ForegroundColor Yellow
        Write-Host ""
    }
}

if ($BiosSettingsHits.Count -gt 0) {
    Write-Host "[DETAIL] BIOS OEM-related settings (WMI):" -ForegroundColor Cyan
    $BiosSettingsHits | Select-Object CurrentSetting | Format-Table -AutoSize | Out-Host
    Write-Host ""
}

if ($OemServices.Count -gt 0) {
    Write-Host "[DETAIL] OEM-like services:" -ForegroundColor Cyan
    $OemServices | Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize | Out-Host
    Write-Host ""
}

if ($OemTasks.Count -gt 0) {
    Write-Host "[DETAIL] OEM-like scheduled tasks:" -ForegroundColor Cyan
    $OemTasks | Select-Object TaskName, TaskPath, State | Format-Table -AutoSize | Out-Host
    Write-Host ""
}

# -----------------------------------------------------------------------------
# Cleanup mode (soft; no disks/BCD touched)
# -----------------------------------------------------------------------------
if (-not $Cleanup) {
    Log-Info "Investigation-only mode. No changes were made."
    Log-Info "For soft cleanup (disable WinRE and OEM services/tasks), re-run with: -Cleanup"
    exit 0
}

Write-Host ""
Log-Warn "================ Cleanup Mode (Soft) ================"
Write-Host "This will NOT modify partitions or BCD."
Write-Host "It can:"
Write-Host "  - disable WinRE (reagentc /disable)"
Write-Host "  - disable OEM-like services (Set-Service ... Disabled)"
Write-Host "  - disable OEM-like scheduled tasks (Disable-ScheduledTask)"
Write-Host ""
$confirm = Read-Host "Proceed with soft cleanup? (y/N)"

if ($confirm -notmatch '^[Yy]$') {
    Log-Info "Cleanup aborted by user."
    exit 0
}

# 1) Disable WinRE if enabled
if ($WinREEnabled) {
    try {
        Log-Warn "Disabling WinRE (Windows Recovery Environment)..."
        & reagentc /disable | Out-Host
        Log-Success "WinRE disabled. You can re-enable later with 'reagentc /enable'."
    } catch {
        Log-Error "Failed to disable WinRE: $_"
    }
}

# 2) Disable OEM services
if ($OemServices.Count -gt 0) {
    foreach ($svc in $OemServices) {
        try {
            Log-Warn "Disabling service: $($svc.Name) ($($svc.DisplayName))"
            Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
            if ($svc.Status -ne 'Stopped') {
                Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Log-Error "Failed to disable service $($svc.Name): $_"
        }
    }
    Log-Success "Attempted to disable OEM-like services."
}

# 3) Disable OEM scheduled tasks
if ($OemTasks.Count -gt 0) {
    foreach ($task in $OemTasks) {
        try {
            Log-Warn "Disabling scheduled task: $($task.TaskPath)$($task.TaskName)"
            Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop | Out-Null
        } catch {
            Log-Error "Failed to disable task $($task.TaskName): $_"
        }
    }
    Log-Success "Attempted to disable OEM-like scheduled tasks."
}

Write-Host ""
Log-Success "Soft cleanup complete."
Log-Info "Next steps for a real trust reset usually involve:"
Write-Host "  - Booting from a live USB"
Write-Host "  - Wiping the disk header (sgdisk --zap-all / dd, etc.)"
Write-Host "  - Reinstalling Linux onto a clean GPT with no OEM/WinRE partitions"
