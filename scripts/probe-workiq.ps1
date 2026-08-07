<#
.SYNOPSIS
    Diagnostic: drives the WorkIQ stdio MCP server over JSON-RPC to list its tools.

.DESCRIPTION
    Used during setup/troubleshooting to confirm the WorkIQ MCP server starts and to
    capture its real tool inventory without going through Cursor. Writes the raw
    tools/list response so the tool names and schemas can be inspected.

.PARAMETER TimeoutSeconds
    How long to wait for the server to respond before giving up.

.PARAMETER OutputPath
    Optional file to write the raw JSON-RPC responses to.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 90,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$initialize = @{
    jsonrpc = '2.0'
    id      = 1
    method  = 'initialize'
    params  = @{
        protocolVersion = '2024-11-05'
        capabilities    = @{}
        clientInfo      = @{ name = 'workiq-probe'; version = '1.0.0' }
    }
} | ConvertTo-Json -Depth 10 -Compress

$initialized = @{ jsonrpc = '2.0'; method = 'notifications/initialized' } | ConvertTo-Json -Compress
$toolsList = @{ jsonrpc = '2.0'; id = 2; method = 'tools/list' } | ConvertTo-Json -Compress

$stdinFile = Join-Path ([System.IO.Path]::GetTempPath()) "workiq-probe-in-$([guid]::NewGuid()).jsonl"
$stdoutFile = Join-Path ([System.IO.Path]::GetTempPath()) "workiq-probe-out-$([guid]::NewGuid()).txt"
$stderrFile = Join-Path ([System.IO.Path]::GetTempPath()) "workiq-probe-err-$([guid]::NewGuid()).txt"

# The server reads newline-delimited JSON-RPC from stdin.
Set-Content -LiteralPath $stdinFile -Value "$initialize`n$initialized`n$toolsList" -Encoding utf8

Write-Host "Starting WorkIQ MCP server..." -ForegroundColor Cyan
$proc = Start-Process -FilePath 'npx.cmd' `
    -ArgumentList '-y', '@microsoft/workiq@latest', 'mcp' `
    -RedirectStandardInput $stdinFile `
    -RedirectStandardOutput $stdoutFile `
    -RedirectStandardError $stderrFile `
    -NoNewWindow -PassThru

if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    Write-Host "Server still running after ${TimeoutSeconds}s (expected for a stdio server) - stopping it." -ForegroundColor Yellow
    try { $proc.Kill($true) } catch { }
    Start-Sleep -Seconds 1
}

$stdout = if (Test-Path $stdoutFile) { Get-Content -LiteralPath $stdoutFile -Raw } else { '' }
$stderr = if (Test-Path $stderrFile) { Get-Content -LiteralPath $stderrFile -Raw } else { '' }

Write-Host "`n===== STDOUT =====" -ForegroundColor Green
if ($stdout) { Write-Output $stdout } else { Write-Host '(empty)' -ForegroundColor DarkGray }

Write-Host "`n===== STDERR =====" -ForegroundColor Yellow
if ($stderr) { Write-Output $stderr } else { Write-Host '(empty)' -ForegroundColor DarkGray }

if ($OutputPath) {
    Set-Content -LiteralPath $OutputPath -Value "===== STDOUT =====`n$stdout`n===== STDERR =====`n$stderr"
    Write-Host "`nWrote $OutputPath" -ForegroundColor Cyan
}

Remove-Item -LiteralPath $stdinFile, $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
