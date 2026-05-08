<#
.SYNOPSIS
    Runs a coding agent (Claude Code or Codex) inside Docker against a local workspace.

.PARAMETER Agent
    Which agent to run: "claude" or "codex"

.PARAMETER Workspace
    Absolute path to the project directory to mount into the container.
    Defaults to the current directory.

.PARAMETER Build
    Rebuild the agent Docker image before running (e.g. after a package update).

.EXAMPLE
    .\scripts\Run-Agent.ps1 -Agent claude
    .\scripts\Run-Agent.ps1 -Agent codex -Workspace C:\Users\colin\Source\repos\my-project
    .\scripts\Run-Agent.ps1 -Agent claude -Build
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("claude", "codex", "aider")]
    [string]$Agent,

    [string]$Workspace = (Get-Location).Path,

    [switch]$Build
)

$ErrorActionPreference = "Stop"

$repoRoot    = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $repoRoot "docker-compose.yml"

# Validate workspace path
if (-not (Test-Path $Workspace -PathType Container)) {
    Write-Error "Workspace not found: $Workspace"
    exit 1
}
$Workspace = (Resolve-Path $Workspace).Path

# Guard: ensure the server stack is running before launching an agent
$serverUp = docker ps --filter "name=llama-server" --filter "status=running" -q 2>$null
if (-not $serverUp) {
    Write-Error "llama-server is not running.`nStart the server first:`n  .\scripts\Start-Server.ps1 -Model <model-key>"
    exit 1
}

$service = switch ($Agent) {
    "claude" { "claude-code" }
    "codex"  { "codex" }
    "aider"  { "aider" }
}
$env:WORKSPACE = $Workspace

Write-Host ""
Write-Host "Starting $Agent in Docker" -ForegroundColor Cyan
Write-Host "  Workspace: $Workspace"
Write-Host "  Service:   $service"
Write-Host ""

$baseArgs = @("--file", $composeFile, "--profile", "agents")

# Optionally rebuild the image
if ($Build) {
    Write-Host "Building image for $service..." -ForegroundColor Yellow
    docker compose @baseArgs build $service
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Image build failed."
        exit $LASTEXITCODE
    }
}

# --no-deps: server is already managed by Start-Server.ps1; don't let compose
#            reconcile it (would fail with MODEL_FILE unset in this session)
docker compose @baseArgs run --rm --no-deps $service

if ($LASTEXITCODE -ne 0) {
    Write-Error "Agent exited with code $LASTEXITCODE"
    exit $LASTEXITCODE
}
