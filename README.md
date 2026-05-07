# Local Coding Agents

Run coding agents (Claude Code, OpenAI Codex) against local LLMs instead of cloud APIs. The entire stack runs in Docker: model inference via [llama.cpp](https://github.com/ggml-org/llama.cpp), an API translation proxy, and the agents themselves.

## Purpose

This repo lets you benchmark and experiment with local open-weight models as drop-in replacements for Claude and GPT in real coding agent workflows — without sending code to external APIs or paying per token.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Host machine                                        │
│                                                      │
│  .\scripts\Run-Agent.ps1 -Agent claude               │
│         │                                            │
│  ┌──────▼──────────────────────────────────────┐    │
│  │  Docker network                              │    │
│  │                                              │    │
│  │  ┌─────────────┐   Anthropic API             │    │
│  │  │ claude-code │──────────────►┐             │    │
│  │  └─────────────┘               │             │    │
│  │                          ┌─────▼──────┐      │    │
│  │                          │  LiteLLM   │      │    │
│  │                          │  :4000     │      │    │
│  │                          └─────┬──────┘      │    │
│  │  ┌─────────────┐               │ OpenAI API  │    │
│  │  │    codex    │───────────────┤             │    │
│  │  └─────────────┘               │             │    │
│  │                          ┌─────▼──────┐      │    │
│  │                          │llama-server│      │    │
│  │                          │  :8080     │      │    │
│  │                          └─────┬──────┘      │    │
│  └────────────────────────────────┼─────────────┘    │
│                                   │                   │
│                             ./models/*.gguf           │
│                             (NVIDIA GPU / CUDA)       │
└─────────────────────────────────────────────────────┘
```

**Services:**

| Container | Image | Purpose |
|-----------|-------|---------|
| `llama-server` | `ghcr.io/ggml-org/llama.cpp:server-cuda` | Loads a GGUF model and serves an OpenAI-compatible API on `:8080` |
| `litellm` | `ghcr.io/berriai/litellm:main-latest` | Translates Claude Code's Anthropic Messages API into OpenAI format and forwards to llama-server on `:4000` |
| `claude-code` | Built from `Dockerfile.agents` | Claude Code CLI pre-configured to point at LiteLLM |
| `codex` | Built from `Dockerfile.agents` | OpenAI Codex CLI pre-configured to point at llama-server directly |

`llama-server` and `litellm` are always-on services (started with `Start-Server.ps1`). `claude-code` and `codex` are on-demand — each run spawns a fresh container, mounts your project directory, and removes itself on exit.

## Prerequisites

- **Docker Desktop** with WSL2 backend enabled
- **NVIDIA GPU** with the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed in WSL2
- **PowerShell 7+** (`pwsh`)

Verify GPU access is working inside Docker before proceeding:
```powershell
docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi
```

## Getting Started

### 1. Clone the repo

```powershell
git clone https://github.com/colin-geo/local-coding-agents-testing.git
cd local-coding-agents-testing
```

### 2. Download a model

Models are stored in `./models/` (gitignored). The registry at `config/models.json` defines available models with their HuggingFace download URLs and recommended runtime parameters.

```powershell
# ~5.8 GB — fits entirely on an 8 GB GPU
.\scripts\Download-Model.ps1 -Model qwen2.5-coder-7b

# ~19.5 GB — partial GPU offload, requires 32+ GB system RAM
.\scripts\Download-Model.ps1 -Model qwen2.5-coder-32b
```

Downloads resume automatically if interrupted.

### 3. Start the server stack

```powershell
.\scripts\Start-Server.ps1 -Model qwen2.5-coder-7b
```

This starts `llama-server` and `litellm` as detached Docker services. The model takes ~60 seconds to load; LiteLLM waits for the health check before starting.

**Profiles** control context window and parallel slots:

| Profile | Context | Parallel | Use when |
|---------|---------|----------|----------|
| `quality` | Full (32K for 7B) | 1 | Default — required for coding agents whose system prompts are large |
| `fast` | Half | 1 | Quick experiments, scripts, smaller prompts |

```powershell
.\scripts\Start-Server.ps1 -Model qwen2.5-coder-7b -Profile quality
```

### 4. Build the agent images (first time only)

```powershell
docker compose --profile agents build
```

This pulls a Node.js base image and installs Claude Code and Codex CLI. Only needed once, or after updating agent versions.

### 5. Run an agent

```powershell
# Mount the current directory as the workspace
.\scripts\Run-Agent.ps1 -Agent claude

# Mount a specific project
.\scripts\Run-Agent.ps1 -Agent claude -Workspace C:\path\to\your\project

# Run Codex instead
.\scripts\Run-Agent.ps1 -Agent codex -Workspace C:\path\to\your\project
```

The agent starts interactively inside Docker with your project mounted at `/workspace`. The server must be running first.

## Switching models

```powershell
.\scripts\Stop-Server.ps1
.\scripts\Start-Server.ps1 -Model qwen2.5-coder-32b -Profile quality
```

## Adding models

Add an entry to `config/models.json`:

```json
"my-model": {
  "display_name": "My Model (Q4_K_M)",
  "hf_repo": "org/repo-GGUF",
  "hf_file": "model-Q4_K_M.gguf",
  "hf_url": "https://huggingface.co/org/repo-GGUF/resolve/main/model-Q4_K_M.gguf",
  "n_gpu_layers": -1,
  "n_num_moe": null,
  "ctx_size": 32768,
  "cache_type_k": "f16",
  "cache_type_v": "f16",
  "suggested_profile": "quality"
}
```

All scripts pick it up automatically. Set `n_num_moe` to an integer for MoE models (controls how many expert layers stay on GPU). Use `"cache_type_k": "q8_0"` to halve KV cache VRAM on large models or long contexts.

## Script reference

| Script | Description |
|--------|-------------|
| `Download-Model.ps1 -Model <key>` | Download a GGUF model from HuggingFace |
| `Start-Server.ps1 -Model <key> [-Profile fast\|quality]` | Start llama-server + LiteLLM |
| `Stop-Server.ps1` | Stop the server stack |
| `Run-Agent.ps1 -Agent claude\|codex [-Workspace <path>]` | Run a coding agent container |
| `Set-AgentEnv.ps1 [-Agent claude\|codex\|all]` | Set env vars to use agents on the host instead of in Docker |

## Using agents on the host (alternative to Docker)

If you prefer running `claude` or `codex` directly on your machine rather than inside a container:

```powershell
# Dot-source to set env vars in the current session
. .\scripts\Set-AgentEnv.ps1

# Then use the CLIs normally (requires them installed on the host)
claude "refactor this function"
codex "write unit tests for this file"
```
