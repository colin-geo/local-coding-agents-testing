<#
.SYNOPSIS
    Starts llama-server and the LiteLLM proxy via Docker Compose.

.PARAMETER Model
    Model key from config/models.json (e.g., "qwen2.5-coder-7b")

.PARAMETER Profile
    "fast"    - halved context window, 1 parallel slot (faster TTFT, lower VRAM)
    "quality" - full context window, 2 parallel slots
    Defaults to the model's suggested_profile from the registry.

.PARAMETER Detach
    Run containers in the background. Default: $true

.EXAMPLE
    .\scripts\Start-Server.ps1 -Model qwen2.5-coder-7b
    .\scripts\Start-Server.ps1 -Model qwen2.5-coder-32b -Profile quality
    .\scripts\Start-Server.ps1 -Model qwen2.5-coder-7b -Detach:$false
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Model,

    [ValidateSet("fast", "quality")]
    [string]$Profile = "",

    [bool]$Detach = $true
)

$ErrorActionPreference = "Stop"

$repoRoot     = Split-Path -Parent $PSScriptRoot
$registryPath = Join-Path $repoRoot "config\models.json"
$modelsDir    = Join-Path $repoRoot "models"
$composeFile  = Join-Path $repoRoot "docker-compose.yml"

if (-not (Test-Path $registryPath)) {
    Write-Error "Registry not found: $registryPath"
    exit 1
}
$registry = Get-Content $registryPath -Raw | ConvertFrom-Json

$entry = $registry.$Model
if ($null -eq $entry) {
    $available = ($registry | Get-Member -MemberType NoteProperty).Name -join ", "
    Write-Error "Unknown model '$Model'. Available: $available"
    exit 1
}

$modelPath = Join-Path $modelsDir $entry.hf_file
if (-not (Test-Path $modelPath)) {
    Write-Error "Model file not found: $modelPath`nRun:  .\scripts\Download-Model.ps1 -Model $Model"
    exit 1
}

if ($Profile -eq "") { $Profile = $entry.suggested_profile }

$ctxSize = $entry.ctx_size
$parallel = 1

switch ($Profile) {
    "fast" {
        $ctxSize  = [math]::Max(4096, [int]($entry.ctx_size / 2))
        $parallel = 1
    }
    "quality" {
        $ctxSize  = $entry.ctx_size
        $parallel = 1
    }
}

# Set env vars consumed by docker-compose.yml variable substitution
$env:MODEL_FILE    = $entry.hf_file
$env:N_GPU_LAYERS  = [string]$entry.n_gpu_layers
$env:CTX_SIZE      = [string]$ctxSize
$env:PARALLEL      = [string]$parallel
$env:CACHE_TYPE_K  = $entry.cache_type_k
$env:CACHE_TYPE_V  = $entry.cache_type_v
$env:MODEL_ALIAS   = $Model

# Only set N_CPU_MOE when the registry entry specifies it (MoE models only)
if ($null -ne $entry.n_cpu_moe) {
    $env:N_CPU_MOE = [string]$entry.n_cpu_moe
} else {
    # Clear any value from a previous run so the compose var expands to empty
    Remove-Item -Path "env:N_CPU_MOE" -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Starting local LLM server" -ForegroundColor Cyan
Write-Host "  Model:        $($entry.display_name)"
Write-Host "  Profile:      $Profile"
Write-Host "  GPU layers:   $($entry.n_gpu_layers)"
if ($null -ne $entry.n_cpu_moe) {
    Write-Host "  MoE CPU:      $($entry.n_cpu_moe) expert layers on CPU"
}
Write-Host "  Context:      $ctxSize tokens"
Write-Host "  Parallel:     $parallel slot(s)"
Write-Host "  KV cache:     k=$($entry.cache_type_k)  v=$($entry.cache_type_v)"
Write-Host ""
Write-Host "  llama-server  ->  http://localhost:8080/v1"
Write-Host "  LiteLLM proxy ->  http://localhost:4000"
Write-Host ""

# Verify Docker is accessible before attempting compose
try {
    docker compose version 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "non-zero exit" }
} catch {
    Write-Error "Docker is not running or 'docker compose' is not available. Start Docker Desktop first."
    exit 1
}

$upArgs = @("--file", $composeFile, "up", "--remove-orphans")
if ($Detach) { $upArgs += "-d" }

docker compose @upArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "docker compose up failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

if ($Detach) {
    Write-Host ""
    Write-Host "Containers started." -ForegroundColor Green
    Write-Host "Model loading may take 1-2 minutes. LiteLLM waits for llama-server health before starting."
    Write-Host ""
    Write-Host "Next — set agent env vars (dot-source required):" -ForegroundColor Yellow
    Write-Host "  . .\scripts\Set-AgentEnv.ps1"
    Write-Host ""
    Write-Host "To stop:  .\scripts\Stop-Server.ps1"
}
