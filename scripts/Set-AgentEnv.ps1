<#
.SYNOPSIS
    Sets environment variables in the current session to connect coding agents
    to the local LLM server.

.DESCRIPTION
    IMPORTANT: Dot-source this script so variables take effect in your session:
        . .\scripts\Set-AgentEnv.ps1

    Claude Code  -> LiteLLM proxy at http://localhost:4000  (Anthropic API format)
    Codex CLI    -> llama-server at http://localhost:8080/v1 (OpenAI API format)

.PARAMETER Agent
    Which agent to configure: "claude", "codex", or "all" (default: "all")

.EXAMPLE
    . .\scripts\Set-AgentEnv.ps1
    . .\scripts\Set-AgentEnv.ps1 -Agent claude
    . .\scripts\Set-AgentEnv.ps1 -Agent codex
#>
param(
    [ValidateSet("claude", "codex", "all")]
    [string]$Agent = "all"
)

function Set-EnvVar {
    param([string]$Name, [string]$Value)
    Set-Item -Path "env:$Name" -Value $Value
    Write-Host "  `$env:$Name = `"$Value`"" -ForegroundColor Cyan
}

Write-Host ""

if ($Agent -eq "claude" -or $Agent -eq "all") {
    Write-Host "Claude Code CLI  ->  http://localhost:4000  (via LiteLLM proxy)" -ForegroundColor Yellow
    Set-EnvVar "ANTHROPIC_BASE_URL" "http://localhost:4000"
    Set-EnvVar "ANTHROPIC_API_KEY"  "local"
    Write-Host ""
}

if ($Agent -eq "codex" -or $Agent -eq "all") {
    Write-Host "OpenAI Codex CLI  ->  http://localhost:8080/v1  (direct to llama-server)" -ForegroundColor Yellow
    Set-EnvVar "OPENAI_BASE_URL" "http://localhost:8080/v1"
    Set-EnvVar "OPENAI_API_KEY"  "local"
    Write-Host ""
}

Write-Host "Environment set. Variables persist until this terminal is closed." -ForegroundColor Green
Write-Host ""
Write-Host "Verify server readiness:" -ForegroundColor DarkGray
Write-Host "  Invoke-RestMethod http://localhost:8080/health"
Write-Host "  Invoke-RestMethod http://localhost:4000/health"
Write-Host ""
