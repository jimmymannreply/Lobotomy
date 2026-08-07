<#
.SYNOPSIS
    Converts a sweep.md file to sweep.docx using pandoc.

.DESCRIPTION
    Invoked by prompts/sweep.md (Step 7) and prompts/review-and-write.md (Step 4).
    Writes the Word document next to the Markdown source. Exits with a non-zero code
    on any failure so the calling agent can stop before the upload step.

.PARAMETER MarkdownPath
    Path to the source sweep.md.

.PARAMETER DocxPath
    Path to the target sweep.docx.

.PARAMETER ReferenceDoc
    Optional pandoc reference-doc (.docx) used to control styling. If omitted,
    pandoc's default Word styling is used.

.EXAMPLE
    pwsh -File scripts/render-docx.ps1 -MarkdownPath "output/2026-08-06-1200/sweep.md" -DocxPath "output/2026-08-06-1200/sweep.docx"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MarkdownPath,

    [Parameter(Mandatory = $true)]
    [string]$DocxPath,

    [Parameter(Mandatory = $false)]
    [string]$ReferenceDoc
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message, [int]$Code = 1) {
    Write-Error $Message
    exit $Code
}

function Resolve-Pandoc {
    $onPath = Get-Command pandoc -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $candidates = @(
        "$env:LOCALAPPDATA\Pandoc\pandoc.exe",
        "$env:ProgramFiles\Pandoc\pandoc.exe",
        "${env:ProgramFiles(x86)}\Pandoc\pandoc.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

$pandocExe = Resolve-Pandoc
if (-not $pandocExe) {
    Fail "pandoc is not on PATH and was not found in any standard install location. Install with 'winget install --id JohnMacFarlane.Pandoc' and reopen your terminal. See SETUP.md#pandoc-not-found." 2
}

if (-not (Test-Path -LiteralPath $MarkdownPath)) {
    Fail "Markdown source not found: $MarkdownPath" 3
}

$docxDir = Split-Path -Parent -Path $DocxPath
if ($docxDir -and -not (Test-Path -LiteralPath $docxDir)) {
    New-Item -ItemType Directory -Force -Path $docxDir | Out-Null
}

$pandocArgs = @(
    '--from=gfm+yaml_metadata_block'
    '--to=docx'
    '--standalone'
    "--output=$DocxPath"
    $MarkdownPath
)

if ($ReferenceDoc) {
    if (-not (Test-Path -LiteralPath $ReferenceDoc)) {
        Fail "Reference doc not found: $ReferenceDoc" 4
    }
    $pandocArgs = @("--reference-doc=$ReferenceDoc") + $pandocArgs
}

Write-Host "Rendering '$MarkdownPath' -> '$DocxPath' via pandoc ($pandocExe)..." -ForegroundColor Cyan
& $pandocExe @pandocArgs
if ($LASTEXITCODE -ne 0) {
    Fail "pandoc exited with code $LASTEXITCODE" $LASTEXITCODE
}

if (-not (Test-Path -LiteralPath $DocxPath)) {
    Fail "pandoc reported success but $DocxPath was not created." 5
}

$sizeKb = [math]::Round((Get-Item -LiteralPath $DocxPath).Length / 1KB, 1)
Write-Host "Wrote $DocxPath ($sizeKb KB)" -ForegroundColor Green
exit 0
