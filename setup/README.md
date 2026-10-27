# Mono-kin Setup Guide

This folder contains the automated bootstrap script for setting up the Mono-kin environment on any new machine or WSL instance.

## How to Get Started

1. Open your terminal in the root of the repository (`mono-kin/`).
2. Run the setup script:
   ```bash
   bash setup/bootstrap.sh
   ```

Optional flags:

```bash
bash setup/bootstrap.sh --model devstral:24b              # skip the model menu
bash setup/bootstrap.sh --model qwen3:8b,devstral:24b     # several models, comma separated
bash setup/bootstrap.sh --model all                       # every model in the menu (~80GB)
bash setup/bootstrap.sh --update                          # also update Claude Code, Ollama, and uv
bash setup/bootstrap.sh --skip-test                       # skip the final smoke test
```

### The Bootstrap Script (`setup/bootstrap.sh`)

This script is safe to run multiple times: it skips anything already installed, and only updates tools when you pass `--update`. It automates the environment configuration via the following checks:

1. **Claude Code**: 
   - Installs the `claude` CLI with the official native installer (no Node.js or `npm` required).
   - On WSL, detects if `claude` resolves to the Windows install (`/mnt/c/...`), installs a Linux copy, and puts `~/.local/bin` first in your `PATH` so the Linux one wins. The script stops with an error if the Windows one still takes priority.
2. **Core Tools**: Installs the following tools, if missing:
   - `ollama` engine (via the install script on Linux, Homebrew on macOS)
   - `uv` Python manager
3. **Python Initialization**: 
   - If the `agent/` folder doesn't exist, it runs `uv init agent`. 
   - It then runs `uv sync` to install or update dependencies.
4. **Hardware Detection**: 
   - Reads your RAM and, if `nvidia-smi` works, your GPU's VRAM. VRAM is used as the model budget when a GPU is found, otherwise RAM (unified memory on a Mac).
   - Uses it to suggest a default model and to choose the context size (16k under 12GB, otherwise 32k).
5. **Ollama Server**: 
   - If Ollama isn't already running, starts it with the detected context size, flash attention, and a quantized context cache. Logs go to `setup/ollama_server.log`.
   - If Ollama is already running (for example as a systemd service), the script leaves it alone and prints how to set these yourself.
6. **Model Downloads**: 
   - Shows the model menu (see below). You can pick one model, several (for example `1,3`), a whole group, or everything.
   - Warns when a model is bigger than your detected memory.
   - Records what was pulled in `setup/.models` so teardown can remove them.
7. **Smoke Test**: 
   - Runs `ollama launch claude --model <model> --yes -- -p "Reply with exactly: OK"` to confirm Claude Code can talk to your local model without any login. It uses the recommended model if you installed it, otherwise the lightest one you installed.
   - Claude Code is routed to Ollama by `ollama launch`, so no environment variables are added to your `.bashrc` or `.zshrc`, and no Anthropic API key or login is needed.

## Models

Download sizes are approximate. Models marked "untested" have not been verified with Claude Code yet.

| Tier | Model | Size | Roughly fits | Notes |
|---|---|---|---|---|
| Lightweight | `qwen3:8b` | ~5GB | 6-8GB VRAM, or 8-16GB RAM | General purpose, weaker tool use |
| Lightweight | `qwen3.5:9b` | ~7GB | 6-8GB VRAM, or 8-16GB RAM | Newer lightweight |
| Mid-size | `devstral:24b` | ~14GB | 16-24GB VRAM or unified memory | Agentic coding specialist (untested) |
| High-end | `qwen3.6:27b` | ~17GB | 24-32GB+ | Newer Qwen coder (untested) |
| High-end | `qwen3.8:27b` | ~18GB | 24-32GB+ | Newest Qwen (untested) |
| High-end | `qwen3-coder:30b` | ~19GB | 24-32GB+ | Coding-tuned, long context |

The model needs to support tool calling for Claude Code to work. Before trying other models, check that the model's page on ollama.com has the `tools` tag.

If you pick a model that is bigger than your memory, it still runs but part of it falls back to the CPU, which is much slower. See `PERFORMANCE.md` for how to diagnose this.

## How to Start Coding

After the setup script completes, open a new terminal (or run `source ~/.bashrc`) so the `PATH` change takes effect. 

To start your coding agent, use `ollama launch claude` and specify a model you downloaded:

```bash
ollama launch claude --model qwen3:8b          # lightweight
ollama launch claude --model devstral:24b      # mid-size
ollama launch claude --model qwen3-coder:30b   # high-end
```

Run `ollama launch claude` with no arguments to pick a model from a menu instead. Inside Claude Code, run `/status` to confirm the connection.

> Don't start plain `claude` without `ollama launch`: it won't be routed to Ollama and will ask you to log in to Anthropic.

## Safe Teardown (`setup/teardown.sh`)

If you want to test the setup from scratch or remove the Mono-kin workspace safely, run the teardown script from the root of the repository:

```bash
bash setup/teardown.sh        # asks before each step
bash setup/teardown.sh --yes  # no prompts (also deletes ~/.claude* and the pulled models)
```

**What this script does (Safely):**
- Deletes the `agent/` directory (and its isolated Python virtual environment). Commit any code in `agent/` first.
- Deletes `setup/.models` and `setup/ollama_server.log`.
- Uninstalls the native Claude Code install (`~/.local/bin/claude` and `~/.local/share/claude`), and the old `@anthropic-ai/claude-code` npm package if it's present.
- Removes the Claude Code `PATH` block, and any old routing variables from the previous version of the script, from your `.bashrc` or `.zshrc`.
- Asks before deleting Claude Code settings and login state (`~/.claude`, `~/.claude.json`).
- Asks before removing the Ollama models listed in `setup/.models`.
- **Note:** It intentionally leaves `ollama`, `uv`, `nvm`, and Node.js installed on your machine, as these are global system utilities that other software may rely on. It also doesn't stop a running Ollama server.

## Cleaning Up After the Old Bootstrap

If you ran the previous version of the bootstrap (npm-based, with `ANTHROPIC_BASE_URL` in your shell profile), run the teardown first, then these commands for what teardown doesn't cover:

```bash
# 1. Remove all models the old bootstrap could have pulled
curl -sf http://localhost:11434 >/dev/null || { nohup ollama serve >/dev/null 2>&1 & sleep 4; }
ollama rm qwen3:8b qwen3.5:9b qwen3-coder:30b 2>/dev/null
ollama list

# 2. Stop the old Ollama server (it was started without the right settings)
pkill -f "ollama serve" 2>/dev/null
sudo systemctl stop ollama 2>/dev/null   # only matters if Ollama runs as a systemd service

# 3. Remove the old npm-installed Claude Code (needs nvm loaded to find npm)
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
command -v npm >/dev/null && npm uninstall -g @anthropic-ai/claude-code

# 4. Leftover files from the old script
rm -f setup/ollama_server.log

# 5. Clear the shell's cached command paths
hash -r
```

Then verify the clean state:

```bash
which -a claude                 # should show nothing, or only a /mnt/c/... Windows path
ls ~/.local/bin/claude          # should say "No such file"
pgrep -a ollama                 # should print nothing
grep -n -E 'ANTHROPIC|OLLAMA|claude-code|Claude Code' ~/.bashrc ~/.zshrc 2>/dev/null   # should print nothing
ls agent 2>&1 | head -1         # should say "No such file"
```

Open a new terminal and run `bash setup/bootstrap.sh`.

**Optional:** `nvm` is no longer used by the bootstrap. To remove it, run `rm -rf ~/.nvm`, then delete the three nvm lines (`export NVM_DIR=...` and the two `[ -s "$NVM_DIR/..." ]` lines) from `~/.bashrc` and `~/.zshrc` by hand. Skip this if other projects use Node.

## Troubleshooting

- **Still asks you to log in to Anthropic**: You started plain `claude`. Use `ollama launch claude --model <model>` instead. If the login screen persists, run `/logout` inside Claude Code or delete `~/.claude.json`.
- **`ollama launch` isn't recognized**: Your Ollama is too old. Run `bash setup/bootstrap.sh --update`.
- **`claude` points to the Windows install (WSL)**: Open a new terminal after bootstrap, then check `which claude`. It should be `~/.local/bin/claude`.
- **Slow responses**: Run `ollama ps` while Claude Code is open. A CPU/GPU split means the model doesn't fit in your memory. Choose a smaller model, or see `PERFORMANCE.md`.
- **Model errors on tool calls or ignores instructions**: The model may not support tool calling, or the context is too small. Check for the `tools` tag on the model's page, and keep the context at 16k or above.
- **`ollama pull` says a model tag doesn't exist**: The new model names (`devstral:24b`, `qwen3.6:27b`, `qwen3.8:27b`) came from third-party roundups. Check the exact tag on ollama.com/library and edit `ALL_MODELS` in `bootstrap.sh`.