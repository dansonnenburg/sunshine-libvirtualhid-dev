<#
.SYNOPSIS
    Build the Sunshine fork into a Windows MSI installer locally.

.DESCRIPTION
    Mirrors the native Windows build in .github/workflows/ci-windows.yml: it uses an
    MSYS2 UCRT64 toolchain to configure with CMake + Ninja, compiles, then runs
    'cpack -G WIX' to produce the MSI (and a portable ZIP). The resulting installer is
    copied to the output directory.

    Prerequisites (same as CI):
      - MSYS2 installed at -Msys2Root (default C:\msys64) with the UCRT64 toolchain and
        the mingw-w64-ucrt-x86_64 dependencies listed in ci-windows.yml (boost, cmake,
        gcc, ninja, qt6-static, openssl, opus, miniupnpc, nlohmann-json, onevpl,
        cppwinrt, curl-winssl, MinHook, nsis, etc.).
      - .NET SDK on PATH (dotnet) so CPack WIX can fetch the wix tool.
      - Node.js on PATH (the web UI is built during configure).
      - All git submodules checked out (this script runs 'git submodule update').

.PARAMETER Version
    Version string embedded in the build (default 0.0.0).

.PARAMETER Commit
    Commit hash embedded in the build (default: current HEAD short hash).

.PARAMETER BuildDir
    CMake build directory (default: build-package under the repo root).

.PARAMETER OutDir
    Directory that receives the built MSI/ZIP (default: dist under the repo root).

.PARAMETER Msys2Root
    MSYS2 install root (default C:\msys64).

.PARAMETER SkipSubmodules
    Skip 'git submodule update --init --recursive'.

.EXAMPLE
    pwsh -File scripts\package.ps1 -Version 2026.1117.1
#>
[CmdletBinding()]
param(
    [string] $Version = '0.0.0',
    [string] $Commit = '',
    [string] $BuildDir = '',
    [string] $OutDir = '',
    [string] $Msys2Root = 'C:\msys64',
    [switch] $SkipSubmodules,
    [switch] $PublishToNas,
    [string] $NasRoot = '\\nas\Apps\installers\sunshine'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot

if (-not $BuildDir) { $BuildDir = Join-Path $repoRoot 'build-package' }
if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'dist' }

$msys2Shell = Join-Path $Msys2Root 'msys2_shell.cmd'
if (-not (Test-Path -LiteralPath $msys2Shell)) {
    throw "MSYS2 not found at '$Msys2Root'. Install MSYS2 or pass -Msys2Root. See .github/workflows/ci-windows.yml for the UCRT64 dependency list."
}

if (-not $Commit) {
    $Commit = (git rev-parse --short HEAD).Trim()
}

Write-Host "Packaging Sunshine fork"
Write-Host "  Version:  $Version"
Write-Host "  Commit:   $Commit"
Write-Host "  BuildDir: $BuildDir"
Write-Host "  OutDir:   $OutDir"
Write-Host "  MSYS2:    $Msys2Root"

if (-not $SkipSubmodules) {
    Write-Host 'Updating submodules...'
    git submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) { throw 'git submodule update failed.' }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# Build the bash command that runs inside the MSYS2 UCRT64 shell. The repo is passed
# through cygpath so CMake sees an MSYS-style path. Mirrors the CI "Build Windows" and
# "Package Windows" steps.
$posixBuildDir = 'build'
$bash = @"
set -euo pipefail
cd "`$(cygpath -u '$repoRoot')"
mkdir -p '$posixBuildDir'
cmake \
  -B '$posixBuildDir' \
  -G Ninja \
  -S . \
  -DBUILD_WERROR=ON \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DSUNSHINE_ASSETS_DIR=assets \
  -DSUNSHINE_PUBLISHER_NAME='LizardByte' \
  -DSUNSHINE_PUBLISHER_WEBSITE='https://app.lizardbyte.dev' \
  -DSUNSHINE_PUBLISHER_ISSUE_URL='https://app.lizardbyte.dev/support'
ninja -C '$posixBuildDir'
cd '$posixBuildDir'
cpack -G WIX
cpack -G ZIP
"@

# Persist the script so quoting survives the handoff to msys2_shell.cmd.
$bashScript = Join-Path $env:TEMP ("sunshine-package-{0}.sh" -f $Commit)
Set-Content -LiteralPath $bashScript -Value ($bash -replace "`r`n", "`n") -NoNewline -Encoding ascii

# Convert the Windows temp path to the MSYS2 POSIX form (C:\x -> /c/x) so bash can run it.
$posixScript = '/' + ($bashScript.Substring(0, 1).ToLower()) + ($bashScript.Substring(2) -replace '\\', '/')

Write-Host 'Running MSYS2 UCRT64 build (this can take a long time)...'
& $msys2Shell -defterm -here -no-start -ucrt64 -c "bash '$posixScript'" 2>&1 | Write-Host
if ($LASTEXITCODE -ne 0) { throw "MSYS2 build failed with exit code $LASTEXITCODE." }

$artifactDir = Join-Path $BuildDir 'cpack_artifacts'
if (-not (Test-Path -LiteralPath $artifactDir)) {
    # CI uses an in-tree 'build' dir; honor whichever one the build produced.
    $artifactDir = Join-Path (Join-Path $repoRoot $posixBuildDir) 'cpack_artifacts'
}

$msi = Get-ChildItem -LiteralPath $artifactDir -Filter '*.msi' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $msi) {
    throw "No MSI found under '$artifactDir'. Check the CPack WIX log at '$artifactDir\_CPack_Packages\win64\WIX\wix.log'."
}

$stamp = ("Sunshine-{0}-{1}.msi" -f $Version, $Commit)
$outMsi = Join-Path $OutDir $stamp
Copy-Item -LiteralPath $msi.FullName -Destination $outMsi -Force

$zip = Get-ChildItem -LiteralPath $artifactDir -Filter '*.zip' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($zip) {
    Copy-Item -LiteralPath $zip.FullName -Destination (Join-Path $OutDir ("Sunshine-{0}-{1}-lite.zip" -f $Version, $Commit)) -Force
}

Write-Host ''
Write-Host "MSI written to: $outMsi"
Write-Host "Install it with: pwsh -File scripts\install.ps1 -MsiPath `"$outMsi`""

# Record a small build log next to the artifacts (the GitLab pipeline keeps this, not the MSI).
$log = Join-Path $OutDir ("build-{0}-{1}.log" -f $Version, $Commit)
"Sunshine package build`nVersion: $Version`nCommit:  $Commit`nMSI:     $outMsi" | Set-Content -LiteralPath $log -Encoding ascii

# Publish to the NAS for the deploy leg (app-packaging convention). robocopy returns
# 0-7 on success and >=8 on real failure, so only >=8 is a failure.
if ($PublishToNas) {
    $destDir = Join-Path $NasRoot $Version
    Write-Host "Publishing MSI to NAS: $destDir"
    robocopy (Split-Path -Parent $outMsi) $destDir (Split-Path -Leaf $outMsi) /R:2 /W:5 /NFL /NDL /NJH /NJS | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ge 8) { throw "robocopy to NAS failed with exit code $rc." }
    $global:LASTEXITCODE = 0
    Write-Host "Published: $(Join-Path $destDir (Split-Path -Leaf $outMsi))"
}
