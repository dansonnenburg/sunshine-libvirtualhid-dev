<#
.SYNOPSIS
    Install (or re-install) the Sunshine fork MSI on this machine, preserving config.

.DESCRIPTION
    Re-installs Sunshine safely:
      1. Elevates to Administrator if needed.
      2. Stops SunshineService.
      3. Backs up the existing config directory (paired clients, the credentials CA,
         apps.json, sunshine.conf) to a timestamped folder OUTSIDE the install dir, so
         an uninstall cannot destroy it.
      4. Uninstalls any existing Sunshine (NSIS Uninstall.exe or a prior MSI).
      5. Installs the new MSI silently.
      6. Restores the backed-up config so Moonlight clients stay paired.
      7. Starts the service and verifies the running version.

    Losing config\credentials forces every Moonlight device to re-pair, so the backup
    and restore steps are the point of this script, not an afterthought.

.PARAMETER MsiPath
    Path to the Sunshine MSI to install.

.PARAMETER InstallDir
    Existing/target install directory (default C:\Program Files\Sunshine).

.PARAMETER NoRestoreConfig
    Install fresh without restoring the previous config (forces client re-pairing).

.EXAMPLE
    pwsh -File scripts\install.ps1 -MsiPath .\dist\Sunshine-0.0.0-abc1234.msi
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $MsiPath,
    [string] $InstallDir = 'C:\Program Files\Sunshine',
    [switch] $NoRestoreConfig
)

$ErrorActionPreference = 'Stop'

# --- Resolve MSI path before any elevation relaunch loses the working directory. ---
$MsiPath = (Resolve-Path -LiteralPath $MsiPath).Path
if (-not (Test-Path -LiteralPath $MsiPath)) {
    throw "MSI not found: $MsiPath"
}

# --- Self-elevate. ---
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Elevating to Administrator...'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-MsiPath', "`"$MsiPath`"", '-InstallDir', "`"$InstallDir`"")
    if ($NoRestoreConfig) { $argList += '-NoRestoreConfig' }
    Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $argList -Verb RunAs
    return
}

$serviceName = 'SunshineService'
$configDir = Join-Path $InstallDir 'config'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $env:ProgramData ("Sunshine-config-backups\{0}" -f $stamp)

Write-Host "Installing MSI: $MsiPath"

# --- 1. Stop the service. ---
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne 'Stopped') {
    Write-Host 'Stopping SunshineService...'
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    $svc.WaitForStatus('Stopped', (New-TimeSpan -Seconds 30))
}

# --- 2. Back up config. ---
$haveBackup = $false
if (Test-Path -LiteralPath $configDir) {
    Write-Host "Backing up config to $backupRoot"
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    Copy-Item -LiteralPath $configDir -Destination (Join-Path $backupRoot 'config') -Recurse -Force
    $haveBackup = $true
} else {
    Write-Host 'No existing config directory found; nothing to back up.'
}

# --- 3. Uninstall existing install. ---
$existing = Get-ItemProperty `
    HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, `
    HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
    -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Sunshine*' } | Select-Object -First 1

if ($existing) {
    Write-Host "Uninstalling existing: $($existing.DisplayName) $($existing.DisplayVersion)"
    if ($existing.WindowsInstaller -eq 1 -and $existing.PSChildName -match '^\{.*\}$') {
        # Prior MSI install: remove by product code.
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $existing.PSChildName, '/qn', '/norestart') -Wait -PassThru
        if ($p.ExitCode -notin 0, 1605, 3010) { throw "Uninstall (msiexec) failed with exit code $($p.ExitCode)." }
    } else {
        # NSIS uninstaller. _?= makes it run synchronously in place.
        $uninstaller = Join-Path $InstallDir 'Uninstall.exe'
        if (Test-Path -LiteralPath $uninstaller) {
            $p = Start-Process -FilePath $uninstaller -ArgumentList @('/S', "_?=$InstallDir") -Wait -PassThru
            Start-Sleep -Seconds 3
        } else {
            Write-Host 'Uninstall.exe not found; proceeding to install over the existing files.'
        }
    }
} else {
    Write-Host 'No existing Sunshine registration found.'
}

# --- 4. Install the new MSI. ---
$logPath = Join-Path $env:TEMP ("sunshine-msi-install-{0}.log" -f $stamp)
Write-Host 'Installing new MSI (silent)...'
$p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', "`"$MsiPath`"", '/qn', '/norestart', '/l*v', "`"$logPath`"") -Wait -PassThru
if ($p.ExitCode -notin 0, 3010) {
    throw "MSI install failed with exit code $($p.ExitCode). See log: $logPath"
}
Write-Host "MSI install exit code: $($p.ExitCode) (log: $logPath)"

# --- 5. Restore config so paired clients survive. ---
if ($haveBackup -and -not $NoRestoreConfig) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Stopped') {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        $svc.WaitForStatus('Stopped', (New-TimeSpan -Seconds 30))
    }
    Write-Host 'Restoring previous config (apps, paired clients, credentials)...'
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    Copy-Item -Path (Join-Path $backupRoot 'config\*') -Destination $configDir -Recurse -Force
}

# --- 6. Start and verify. ---
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host 'Starting SunshineService...'
    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
}

$installed = Get-ItemProperty `
    HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, `
    HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
    -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Sunshine*' } | Select-Object -First 1

Write-Host ''
Write-Host 'Install complete.'
if ($installed) { Write-Host "  Installed: $($installed.DisplayName) $($installed.DisplayVersion)" }
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc) { Write-Host "  Service:   $($svc.Status)" }
if ($haveBackup) { Write-Host "  Config backup kept at: $backupRoot" }
Write-Host '  Open the web UI with: pwsh -File scripts\run.ps1'
