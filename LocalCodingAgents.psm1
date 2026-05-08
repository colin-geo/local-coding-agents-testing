<#
.SYNOPSIS
    LocalCodingAgents — PowerShell module for managing the local LLM coding agent stack.

.DESCRIPTION
    Provides cmdlets to control llama-server, LiteLLM, agent containers, and model downloads.

    Add to your PowerShell profile to have these available in every session:
        Import-Module C:\path\to\local-coding-agents\LocalCodingAgents.psm1

    Available commands:
        Get-LLMModel          List models from the registry (shows download status)
        Save-LLMModel         Download a GGUF model from HuggingFace
        Start-LLMServer       Start llama-server + LiteLLM via Docker Compose
        Stop-LLMServer        Stop the server stack
        Get-LLMServerStatus   Show whether containers are running
        Set-LLMAgentEnv       Set env vars to connect agents to the local server
        Start-LLMAgent        Run a coding agent container (claude / aider / codex)
#>

$script:RepoRoot = $PSScriptRoot

# ---------------------------------------------------------------------------

function Get-LLMModel {
    <#
    .SYNOPSIS
        Lists models in the registry with download status, or shows details for one model.
    .EXAMPLE
        Get-LLMModel
        Get-LLMModel -Model qwen2.5-coder-7b
    #>
    [CmdletBinding()]
    param(
        [string]$Model
    )

    $registryPath = Join-Path $script:RepoRoot "config\models.json"
    $modelsDir    = Join-Path $script:RepoRoot "models"
    $registry     = Get-Content $registryPath -Raw | ConvertFrom-Json

    $keys = if ($PSBoundParameters.ContainsKey("Model")) {
        if ($null -eq $registry.$Model) { Write-Error "Unknown model: $Model"; return }
        @($Model)
    } else {
        ($registry | Get-Member -MemberType NoteProperty).Name
    }

    foreach ($key in $keys) {
        $e = $registry.$key
        [PSCustomObject]@{
            Key         = $key
            DisplayName = $e.display_name
            Downloaded  = Test-Path (Join-Path $modelsDir $e.hf_file)
            CtxSize     = $e.ctx_size
            GpuLayers   = $e.n_gpu_layers
            CpuMoE      = $e.n_cpu_moe
            CacheK      = $e.cache_type_k
            CacheV      = $e.cache_type_v
            Profile     = $e.suggested_profile
        }
    }
}

# ---------------------------------------------------------------------------

function Save-LLMModel {
    <#
    .SYNOPSIS
        Downloads a GGUF model from HuggingFace to the ./models/ directory.
    .EXAMPLE
        Save-LLMModel qwen2.5-coder-7b
        Save-LLMModel qwen3.6-35b-a3b -Force
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Model,

        [switch]$Force
    )

    $script  = Join-Path $script:RepoRoot "scripts\Download-Model.ps1"
    $cmdArgs = @("-Model", $Model)
    if ($Force) { $cmdArgs += "-Force" }
    & $script @cmdArgs
}

# ---------------------------------------------------------------------------

function Start-LLMServer {
    <#
    .SYNOPSIS
        Starts llama-server and the LiteLLM proxy via Docker Compose.
    .EXAMPLE
        Start-LLMServer qwen2.5-coder-7b
        Start-LLMServer qwen3.6-35b-a3b -Profile quality
        Start-LLMServer qwen2.5-coder-7b -Detach:$false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Model,

        [ValidateSet("fast", "quality")]
        [string]$Profile,

        [bool]$Detach = $true
    )

    $script  = Join-Path $script:RepoRoot "scripts\Start-Server.ps1"
    $cmdArgs = @("-Model", $Model, "-Detach", $Detach)
    if ($PSBoundParameters.ContainsKey("Profile")) { $cmdArgs += "-Profile", $Profile }
    & $script @cmdArgs
}

# ---------------------------------------------------------------------------

function Stop-LLMServer {
    <#
    .SYNOPSIS
        Stops llama-server and the LiteLLM proxy.
    .EXAMPLE
        Stop-LLMServer
        Stop-LLMServer -Volumes
    #>
    [CmdletBinding()]
    param(
        [switch]$Volumes
    )

    $script  = Join-Path $script:RepoRoot "scripts\Stop-Server.ps1"
    $cmdArgs = @()
    if ($Volumes) { $cmdArgs += "-Volumes" }
    & $script @cmdArgs
}

# ---------------------------------------------------------------------------

function Get-LLMServerStatus {
    <#
    .SYNOPSIS
        Shows whether llama-server and LiteLLM containers are currently running.
    .EXAMPLE
        Get-LLMServerStatus
    #>
    [CmdletBinding()]
    param()

    $llama   = docker ps --filter "name=llama-server" --filter "status=running" -q 2>$null
    $litellm = docker ps --filter "name=litellm"      --filter "status=running" -q 2>$null

    [PSCustomObject]@{
        LlamaServer = if ($llama)   { "Running" } else { "Stopped" }
        LiteLLM     = if ($litellm) { "Running" } else { "Stopped" }
    }
}

# ---------------------------------------------------------------------------

function Set-LLMAgentEnv {
    <#
    .SYNOPSIS
        Sets environment variables to connect coding agents to the local LLM server.
    .DESCRIPTION
        $env: variables are process-wide, so unlike Set-AgentEnv.ps1 this does not
        require dot-sourcing — calling it normally is sufficient.
    .EXAMPLE
        Set-LLMAgentEnv
        Set-LLMAgentEnv -Agent claude
    #>
    [CmdletBinding()]
    param(
        [ValidateSet("claude", "codex", "all")]
        [string]$Agent = "all"
    )

    if ($Agent -in "claude", "all") {
        $env:ANTHROPIC_BASE_URL = "http://localhost:4000"
        $env:ANTHROPIC_API_KEY  = "local"
        Write-Host "Claude Code  ->  `$env:ANTHROPIC_BASE_URL = http://localhost:4000" -ForegroundColor Cyan
    }
    if ($Agent -in "codex", "all") {
        $env:OPENAI_BASE_URL = "http://localhost:8080/v1"
        $env:OPENAI_API_KEY  = "local"
        Write-Host "Codex/Aider  ->  `$env:OPENAI_BASE_URL    = http://localhost:8080/v1" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "Vars set for this session." -ForegroundColor Green
}

# ---------------------------------------------------------------------------

function Start-LLMAgent {
    <#
    .SYNOPSIS
        Runs a coding agent container with your project mounted as /workspace.
    .EXAMPLE
        Start-LLMAgent claude
        Start-LLMAgent aider -Workspace C:\repos\my-project
        Start-LLMAgent claude -Build
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet("claude", "codex", "aider")]
        [string]$Agent,

        [string]$Workspace = (Get-Location).Path,

        [switch]$Build
    )

    $script  = Join-Path $script:RepoRoot "scripts\Run-Agent.ps1"
    $cmdArgs = @("-Agent", $Agent, "-Workspace", $Workspace)
    if ($Build) { $cmdArgs += "-Build" }
    & $script @cmdArgs
}

# ---------------------------------------------------------------------------

Export-ModuleMember -Function `
    Get-LLMModel, `
    Save-LLMModel, `
    Start-LLMServer, `
    Stop-LLMServer, `
    Get-LLMServerStatus, `
    Set-LLMAgentEnv, `
    Start-LLMAgent
