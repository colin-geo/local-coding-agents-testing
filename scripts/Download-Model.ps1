<#
.SYNOPSIS
    Downloads a GGUF model from HuggingFace to the ./models/ directory.

.PARAMETER Model
    Model key from config/models.json (e.g., "qwen2.5-coder-7b")

.PARAMETER Force
    Re-download even if the file already exists.

.EXAMPLE
    .\scripts\Download-Model.ps1 -Model qwen2.5-coder-7b
    .\scripts\Download-Model.ps1 -Model qwen2.5-coder-32b -Force
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Model,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$repoRoot     = Split-Path -Parent $PSScriptRoot
$registryPath = Join-Path $repoRoot "config\models.json"
$modelsDir    = Join-Path $repoRoot "models"

if (-not (Test-Path $registryPath)) {
    Write-Error "Registry not found at: $registryPath"
    exit 1
}
$registry = Get-Content $registryPath -Raw | ConvertFrom-Json

$entry = $registry.$Model
if ($null -eq $entry) {
    $available = ($registry | Get-Member -MemberType NoteProperty).Name -join ", "
    Write-Error "Unknown model '$Model'. Available models: $available"
    exit 1
}

if (-not (Test-Path $modelsDir)) {
    New-Item -ItemType Directory -Path $modelsDir | Out-Null
}

$outFile = Join-Path $modelsDir $entry.hf_file
$url     = $entry.hf_url

if ((Test-Path $outFile) -and -not $Force) {
    $sizeMB = [math]::Round((Get-Item $outFile).Length / 1MB, 1)
    Write-Host "Model already exists: $($entry.hf_file) ($sizeMB MB)" -ForegroundColor Green
    Write-Host "Use -Force to re-download."
    exit 0
}

Write-Host ""
Write-Host "Downloading: $($entry.display_name)" -ForegroundColor Cyan
Write-Host "  From: $url"
Write-Host "  To:   $outFile"
Write-Host ""
Write-Warning "Large file — 7B ~5.8 GB, 32B ~19.5 GB. Use Ctrl+C to cancel; partial files resume automatically."
Write-Host ""

try {
    $startTime = Get-Date
    # -Resume appends to partial files, enabling recovery from interrupted downloads
    Invoke-WebRequest -Uri $url -OutFile $outFile -Resume
    $elapsed = (Get-Date) - $startTime
    $sizeMB  = [math]::Round((Get-Item $outFile).Length / 1MB, 1)
    Write-Host ""
    Write-Host "Download complete: $($entry.hf_file) ($sizeMB MB) in $([math]::Round($elapsed.TotalSeconds))s" -ForegroundColor Green
} catch {
    Write-Error "Download failed: $_"
    exit 1
}
