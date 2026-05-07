<#
.SYNOPSIS
    Stops the llama-server and LiteLLM proxy Docker containers.

.PARAMETER Volumes
    Also remove named volumes.

.EXAMPLE
    .\scripts\Stop-Server.ps1
#>
param(
    [switch]$Volumes
)

$ErrorActionPreference = "Stop"
$repoRoot    = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $repoRoot "docker-compose.yml"

Write-Host "Stopping local LLM services..." -ForegroundColor Yellow

$downArgs = @("--file", $composeFile, "down")
if ($Volumes) { $downArgs += "--volumes" }

docker compose @downArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host "Services stopped." -ForegroundColor Green
} else {
    Write-Error "docker compose down failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
