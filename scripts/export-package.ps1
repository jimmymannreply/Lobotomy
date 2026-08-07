<#
.SYNOPSIS
    Produces a clean, shareable zip of the Reply Daily Activity Monitor with zero user data.

.DESCRIPTION
    Invoked via the /export slash command. Copies the repo to dist/reply-daily-activity-monitor/,
    strips every path that could carry user data (local config, sweep outputs, git history,
    dotenv files, node_modules), verifies the strip list actually landed, and zips the result
    to dist/reply-daily-activity-monitor.zip.

    The final zip is safe to send to anyone at Reply. Recipients follow SETUP.md.

.PARAMETER RepoRoot
    Absolute path to the repository root. Defaults to the parent of this script's folder.

.PARAMETER OutputZip
    Override the target zip path. Defaults to <RepoRoot>/dist/reply-daily-activity-monitor.zip.

.EXAMPLE
    powershell -NoProfile -File scripts/export-package.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [string]$OutputZip
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message, [int]$Code = 1) {
    Write-Error $Message
    exit $Code
}

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent -Path (Split-Path -Parent -Path $MyInvocation.MyCommand.Path)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$distDir = Join-Path $RepoRoot 'dist'
$stageDir = Join-Path $distDir 'reply-daily-activity-monitor'
if (-not $OutputZip) {
    $OutputZip = Join-Path $distDir 'reply-daily-activity-monitor.zip'
}

Write-Host "Repo root: $RepoRoot" -ForegroundColor Cyan
Write-Host "Stage dir: $stageDir" -ForegroundColor Cyan
Write-Host "Output zip: $OutputZip" -ForegroundColor Cyan

# Paths (relative to RepoRoot) that must NEVER appear in the shareable package.
$stripPaths = @(
    '.git',
    '.env',
    '.env.local',
    '.env.development',
    '.env.production',
    'config/monitor.config.json',
    'output',
    'dist',
    'node_modules'
)

# Reset stage dir.
if (Test-Path -LiteralPath $stageDir) {
    Remove-Item -LiteralPath $stageDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

# Also remove any pre-existing zip so we don't accidentally re-ship an old one.
if (Test-Path -LiteralPath $OutputZip) {
    Remove-Item -LiteralPath $OutputZip -Force
}

# Copy repo contents into the stage dir, respecting the strip list.
Write-Host "Copying repo -> stage (excluding user data)..." -ForegroundColor Cyan

$excludeNames = @('.git', 'node_modules', 'output', 'dist')
Get-ChildItem -LiteralPath $RepoRoot -Force | Where-Object {
    $excludeNames -notcontains $_.Name
} | ForEach-Object {
    $dest = Join-Path $stageDir $_.Name
    if ($_.PSIsContainer) {
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
    }
}

# Remove per-path strips (some are files inside copied dirs).
foreach ($rel in $stripPaths) {
    $abs = Join-Path $stageDir $rel
    if (Test-Path -LiteralPath $abs) {
        Write-Host "  strip: $rel" -ForegroundColor Yellow
        Remove-Item -LiteralPath $abs -Recurse -Force
    }
}

# Also nuke any *.env files anywhere in the tree.
Get-ChildItem -LiteralPath $stageDir -Recurse -Force -Include '*.env', '.env*' | ForEach-Object {
    Write-Host "  strip env: $($_.FullName.Substring($stageDir.Length + 1))" -ForegroundColor Yellow
    Remove-Item -LiteralPath $_.FullName -Force
}

# Ensure the two placeholder dirs exist in the shareable copy (recipients need them).
foreach ($needsDir in @('output', 'dist')) {
    $p = Join-Path $stageDir $needsDir
    if (-not (Test-Path -LiteralPath $p)) {
        New-Item -ItemType Directory -Force -Path $p | Out-Null
    }
}
# .gitkeep placeholders so directories are visible after unzip.
foreach ($needsDir in @('output', 'dist')) {
    $keep = Join-Path $stageDir "$needsDir/.gitkeep"
    if (-not (Test-Path -LiteralPath $keep)) {
        Set-Content -LiteralPath $keep -Value "This directory is populated at runtime. See SETUP.md.`n" -NoNewline
    }
}

# Verification: reject the build if anything on the strip list slipped through.
$leaks = @()
if (Test-Path -LiteralPath (Join-Path $stageDir 'config/monitor.config.json')) {
    $leaks += 'config/monitor.config.json'
}
if (Test-Path -LiteralPath (Join-Path $stageDir '.git')) {
    $leaks += '.git'
}
$leakedOutput = Get-ChildItem -LiteralPath (Join-Path $stageDir 'output') -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne '.gitkeep' }
if ($leakedOutput) {
    $leaks += "output/ has user files: $($leakedOutput.Name -join ', ')"
}
$leakedEnv = Get-ChildItem -LiteralPath $stageDir -Recurse -Force -Include '*.env', '.env*' -ErrorAction SilentlyContinue
if ($leakedEnv) {
    $leaks += "leftover env files: $($leakedEnv.FullName -join ', ')"
}

if ($leaks.Count -gt 0) {
    Fail ("Refusing to ship - the following user-data paths were not stripped:`n  - " + ($leaks -join "`n  - "))
}

# Confirm the example config is still there (recipients need it).
if (-not (Test-Path -LiteralPath (Join-Path $stageDir 'config/monitor.config.example.json'))) {
    Fail "config/monitor.config.example.json is missing from the staged copy. Aborting."
}

# Confirm .cursor and prompts made it in.
foreach ($required in @(
        '.cursor/mcp.json',
        '.cursor/rules/monitor.md',
        'prompts/setup.md',
        'prompts/sweep.md',
        'prompts/review-and-write.md',
        'schemas/monitor.config.schema.json',
        'scripts/render-docx.ps1',
        'scripts/validate-config.ps1',
        'scripts/probe-workiq.ps1',
        'scripts/export-package.ps1',
        'automations/daily-sweep.json',
        'README.md',
        'SETUP.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $stageDir $required))) {
        Fail "Required file missing from staged copy: $required"
    }
}

# The shipped MCP config must register workiq-preview as an HTTP server. A `command`
# entry means someone reintroduced the non-existent @microsoft/workiq-preview npm
# package, which fails to start on every recipient machine.
$mcpRaw = Get-Content -LiteralPath (Join-Path $stageDir '.cursor/mcp.json') -Raw
try {
    $mcp = $mcpRaw | ConvertFrom-Json
}
catch {
    Fail "Refusing to ship - .cursor/mcp.json is not valid JSON: $($_.Exception.Message)"
}
$previewEntry = $mcp.mcpServers.'workiq-preview'
if (-not $previewEntry) {
    Fail "Refusing to ship - .cursor/mcp.json does not register 'workiq-preview'."
}
if ($previewEntry.PSObject.Properties.Name -contains 'command') {
    Fail "Refusing to ship - 'workiq-preview' is registered as a command. There is no @microsoft/workiq-preview npm package; it must be an HTTP server pointing at https://workiq.svc.cloud.microsoft/mcp."
}

# Zip it.
Write-Host "Compressing -> $OutputZip" -ForegroundColor Cyan
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $OutputZip -Force

# Report.
$zipInfo = Get-Item -LiteralPath $OutputZip
$sizeKb = [math]::Round($zipInfo.Length / 1KB, 1)
Write-Host ""
Write-Host "Shareable package ready:" -ForegroundColor Green
Write-Host "  $OutputZip ($sizeKb KB)" -ForegroundColor Green
Write-Host "  Recipients follow SETUP.md starting at step 2 Option B." -ForegroundColor Green
Write-Host ""

# Clean up the stage dir (we only keep the zip).
Remove-Item -LiteralPath $stageDir -Recurse -Force
exit 0
