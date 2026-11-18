<#
.SYNOPSIS
    Start Sunshine and open its web UI.

.DESCRIPTION
    Ensures SunshineService is running (starting it, with elevation if required) and
    opens the Sunshine web UI in the default browser. If the service is not installed,
    falls back to launching sunshine.exe directly from the install directory.

.PARAMETER InstallDir
    Sunshine install directory (default C:\Program Files\Sunshine).

.PARAMETER Port
    HTTPS web UI port (default 47990).

.PARAMETER NoBrowser
    Start Sunshine but do not open the browser.

.EXAMPLE
    pwsh -File scripts\run.ps1
#>
[CmdletBinding()]
param(
    [string] $InstallDir = 'C:\Program Files\Sunshine',
    [int] $Port = 47990,
    [switch] $NoBrowser
)

$ErrorActionPreference = 'Stop'

$serviceName = 'SunshineService'
$url = "https://localhost:$Port"

$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -ne 'Running') {
        Write-Host 'Starting SunshineService...'
        try {
            Start-Service -Name $serviceName -ErrorAction Stop
        } catch {
            Write-Host 'Service start needs elevation; relaunching elevated...'
            Start-Process -FilePath (Get-Process -Id $PID).Path `
                -ArgumentList @('-NoProfile', '-Command', "Start-Service -Name $serviceName") -Verb RunAs -Wait
        }
    } else {
        Write-Host 'SunshineService already running.'
    }
} else {
    $exe = Join-Path $InstallDir 'sunshine.exe'
    if (Test-Path -LiteralPath $exe) {
        Write-Host "Service not installed; launching $exe directly..."
        Start-Process -FilePath $exe
    } else {
        throw "SunshineService is not installed and sunshine.exe was not found in $InstallDir. Run scripts\install.ps1 first."
    }
}

# Wait for the web UI to answer before opening the browser.
$deadline = (Get-Date).AddSeconds(20)
$ready = $false
while ((Get-Date) -lt $deadline) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect('127.0.0.1', $Port)
        $tcp.Close()
        $ready = $true
        break
    } catch {
        Start-Sleep -Milliseconds 500
    }
}

if ($ready) {
    Write-Host "Sunshine web UI is up at $url"
} else {
    Write-Host "Sunshine did not answer on port $Port within the timeout; it may still be starting."
}

if (-not $NoBrowser) {
    Write-Host "Opening $url"
    Start-Process $url
}
