param(
    [string] $UpstreamRemote = 'upstream',
    [string] $UpstreamBranch = 'master',
    [string] $ForkRemote = 'origin'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot

$status = git status --porcelain
if ($status) {
    throw 'Working tree is not clean. Commit or stash local changes before syncing upstream.'
}

$branch = git branch --show-current
if (-not $branch) {
    throw 'Cannot sync while HEAD is detached.'
}

git fetch $UpstreamRemote
git rebase "$UpstreamRemote/$UpstreamBranch"
git push $ForkRemote $branch
