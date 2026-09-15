<#
.SYNOPSIS
    Validates a monitor config against the rules in schemas/monitor.config.schema.json.

.DESCRIPTION
    Used by /setup (Step 4) before writing config/monitor.config.json, and useful
    standalone to check the example config still matches expectations.

    Deliberately hand-rolled rather than using Test-Json -Schema: that switch needs
    PowerShell 7+, and most Windows machines (including fresh Reply laptops) only
    have Windows PowerShell 5.1. This script runs on 5.1.

    Exits 0 when valid, 1 when invalid. Failing field paths are printed one per line
    so the caller can re-prompt only the bad fields.

.PARAMETER ConfigPath
    Path to the config JSON to validate. Defaults to config/monitor.config.json.

.EXAMPLE
    powershell -NoProfile -File scripts/validate-config.ps1 -ConfigPath config/monitor.config.example.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent -Path (Split-Path -Parent -Path $MyInvocation.MyCommand.Path)
if (-not $ConfigPath) { $ConfigPath = Join-Path $repoRoot 'config/monitor.config.json' }

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "Config not found: $ConfigPath" -ForegroundColor Red
    Write-Host "Run /setup first." -ForegroundColor Red
    exit 3
}

try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Host "Config is not valid JSON: $ConfigPath" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}

$errors = @()
$warnings = @()

# The shipped example config is a template full of REPLACE_ME placeholders. Filesystem
# and sync-root checks are meaningless against those, so detect template mode and
# report unreplaced placeholders instead.
$isTemplate = (Get-Content -LiteralPath $ConfigPath -Raw) -match 'REPLACE_ME'
if ($isTemplate) {
    Write-Host "Template mode: this config still contains REPLACE_ME placeholders." -ForegroundColor Cyan
    Write-Host "Structural checks will run; filesystem checks will be skipped." -ForegroundColor Cyan
    Write-Host ""
}

function Has($obj, [string]$name) {
    if ($null -eq $obj) { return $false }
    return [bool]($obj.PSObject.Properties.Name -contains $name)
}

function Require-NonEmptyString($obj, [string]$name, [string]$path) {
    if (-not (Has $obj $name)) { return "$path is missing" }
    $v = $obj.$name
    if ($v -isnot [string] -or [string]::IsNullOrWhiteSpace($v)) { return "$path must be a non-empty string" }
    return $null
}

# --- top level ---
foreach ($field in @('monitor_name')) {
    $e = Require-NonEmptyString $config $field $field
    if ($e) { $errors += $e }
}

foreach ($section in @('tenants', 'seed_terms', 'scope', 'output', 'schedule', 'review', 'ambiguity')) {
    if (-not (Has $config $section)) { $errors += "$section is missing" }
}

# --- tenants ---
if (Has $config 'tenants') {
    $tenants = @($config.tenants)
    if ($tenants.Count -lt 1) {
        $errors += "tenants must have at least one entry"
    }
    else {
        for ($i = 0; $i -lt $tenants.Count; $i++) {
            $e = Require-NonEmptyString $tenants[$i] 'name' "tenants[$i].name"
            if ($e) { $errors += $e }
            $e = Require-NonEmptyString $tenants[$i] 'workiq_profile' "tenants[$i].workiq_profile"
            if ($e) { $errors += $e }
        }
        if ($tenants.Count -gt 1) {
            $warnings += "tenants has $($tenants.Count) entries, but v1 sweeps only the first one. Multi-tenant is not implemented."
        }
    }
}

# --- seed_terms ---
if (Has $config 'seed_terms') {
    $seeds = @($config.seed_terms)
    if ($seeds.Count -lt 1) {
        $errors += "seed_terms must have at least one entry"
    }
    foreach ($s in $seeds) {
        if ($s -isnot [string] -or [string]::IsNullOrWhiteSpace($s)) {
            $errors += "seed_terms contains an empty entry"
        }
        elseif ($s.Trim().Length -le 3 -and $s.Trim() -notmatch '\s') {
            $warnings += "seed term '$s' is very short and will match a lot of unrelated content. Prefer specific multi-word phrases."
        }
    }
}

# --- scope ---
if (Has $config 'scope') {
    foreach ($field in @('meetings', 'people_and_chats', 'emails')) {
        if (-not (Has $config.scope $field)) { $errors += "scope.$field is missing" }
    }
    if (Has $config.scope 'meetings') {
        $m = $config.scope.meetings
        if ($m -is [string] -and $m -ne 'all') { $errors += "scope.meetings must be 'all' or an array of meeting titles" }
    }
    if (Has $config.scope 'emails') {
        $em = $config.scope.emails
        if ($em -is [string] -and $em -notin @('all', 'sent_and_received')) {
            $errors += "scope.emails must be 'all', 'sent_and_received', or an array"
        }
    }
}

# --- output ---
if (Has $config 'output') {
    $out = $config.output
    $validModes = @('local_sync', 'sharepoint_api', 'both')

    if (-not (Has $out 'mode')) {
        $errors += "output.mode is missing"
    }
    elseif ($out.mode -notin $validModes) {
        $errors += "output.mode must be one of: $($validModes -join ', ')"
    }
    elseif ($out.mode -ne 'local_sync') {
        $errors += "output.mode is '$($out.mode)', which is not implemented. WorkIQ has no released file-upload tool (upload_blob is unreleased), so only 'local_sync' works. Set it to 'local_sync' and point output.upload_dir at a OneDrive-synced folder."
    }

    $e = Require-NonEmptyString $out 'local_staging_dir' 'output.local_staging_dir'
    if ($e) { $errors += $e }

    if ((Has $out 'mode') -and $out.mode -in @('local_sync', 'both')) {
        $e = Require-NonEmptyString $out 'upload_dir' 'output.upload_dir'
        if ($e) {
            $errors += $e
        }
        elseif (-not $isTemplate) {
            $uploadDir = $out.upload_dir
            $parent = Split-Path -Parent -Path $uploadDir
            if (-not (Test-Path -LiteralPath $uploadDir)) {
                if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                    $errors += "output.upload_dir's parent does not exist, so the folder can't be created: $parent"
                }
                else {
                    $warnings += "output.upload_dir does not exist yet and will need to be created: $uploadDir"
                }
            }
            # $env:OneDrive usually points at the *personal* OneDrive, so a correct
            # work path like "OneDrive - Reply" would look unsynced. Enumerate the
            # OneDrive* directories under the profile as well.
            # Wrap each collection in @(): under PowerShell 5.1 a single-item pipeline
            # result is a bare string, and += on a string concatenates rather than
            # appending, which silently corrupts the root list.
            $syncRoots = @(@($env:OneDrive, $env:OneDriveCommercial) | Where-Object { $_ })
            $syncRoots += @(Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like 'OneDrive*' } |
                    Select-Object -ExpandProperty FullName)
            $syncRoots = @($syncRoots | Sort-Object -Unique)

            if ($syncRoots.Count -gt 0) {
                $normalized = $uploadDir.Replace('/', '\')
                $underSync = $false
                foreach ($root in $syncRoots) {
                    if ($normalized -like "$root*") { $underSync = $true }
                }
                if (-not $underSync) {
                    $warnings += "output.upload_dir is not under a detected OneDrive root, so approved sweeps will stay on this machine and never reach SharePoint: $uploadDir"
                    $warnings += "Detected sync roots on this machine: $($syncRoots -join '; ')"
                }
            }
        }
    }
}

# --- schedule ---
if (Has $config 'schedule') {
    $e = Require-NonEmptyString $config.schedule 'cron' 'schedule.cron'
    if ($e) {
        $errors += $e
    }
    else {
        $fields = @($config.schedule.cron -split '\s+' | Where-Object { $_ })
        if ($fields.Count -ne 5) {
            $errors += "schedule.cron must have exactly 5 whitespace-separated fields, got $($fields.Count): '$($config.schedule.cron)'"
        }
    }
}

# --- review ---
if (Has $config 'review') {
    foreach ($field in @('required_on_scheduled', 'required_on_ondemand')) {
        if (-not (Has $config.review $field)) {
            $errors += "review.$field is missing"
        }
        elseif ($config.review.$field -isnot [bool]) {
            $errors += "review.$field must be true or false"
        }
    }
    if ((Has $config.review 'required_on_scheduled') -and $config.review.required_on_scheduled -eq $false) {
        $warnings += "review.required_on_scheduled is false - scheduled runs will write without asking. The agent rule still requires approval, so this setting will be ignored."
    }
}

# --- ambiguity ---
if (Has $config 'ambiguity') {
    $validPolicies = @('needs_your_call', 'auto_include', 'auto_exclude')
    if (-not (Has $config.ambiguity 'borderline_policy')) {
        $errors += "ambiguity.borderline_policy is missing"
    }
    elseif ($config.ambiguity.borderline_policy -notin $validPolicies) {
        $errors += "ambiguity.borderline_policy must be one of: $($validPolicies -join ', ')"
    }
    if (Has $config.ambiguity 'taxonomy_only_matches') {
        if ($config.ambiguity.taxonomy_only_matches -notin @('exclude', 'needs_your_call')) {
            $errors += "ambiguity.taxonomy_only_matches must be 'exclude' or 'needs_your_call'"
        }
    }
}

if ($isTemplate) {
    $warnings += "This is still the template. Replace every REPLACE_ME value before using it as config/monitor.config.json."
}

# --- report ---
if ($errors.Count -gt 0) {
    Write-Host "Config FAILED validation: $ConfigPath" -ForegroundColor Red
    Write-Host ""
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    if ($warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Warnings:" -ForegroundColor Yellow
        $warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
    exit 1
}

Write-Host "Config is valid: $ConfigPath" -ForegroundColor Green
if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Warnings:" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
exit 0
