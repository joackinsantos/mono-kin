# Performance Guide: Claude Code + Ollama

Claude Code sends a large prompt every session, so it needs a big context window (32k by default). On machines with limited RAM or VRAM this makes things slow. On a machine with a decent GPU, `bash setup/bootstrap.sh` should work with no tuning.

## 1. Diagnose

Run these while Claude Code is open in another terminal:

```bash
free -h      # RAM available to this environment; is swap full?
nvidia-smi   # is the GPU visible? (error = no)
ollama ps    # where is the model running?
```

In `ollama ps`, check the PROCESSOR column:

- `100% GPU`: ideal.
- A split like `60%/40% CPU/GPU`: part of the model runs on CPU, so it's slower.
- `100% CPU`: very slow.

## 2. Fixes (in order)

**1. Raise the WSL memory cap.** WSL2 gets about half your RAM by default. Edit `C:\Users\<you>\.wslconfig`:

```ini
[wsl2]
memory=12GB
swap=8GB
```

Then run `wsl --shutdown` in PowerShell and reopen WSL.

**2. Shrink the context cache.** Restart Ollama with:

```bash
pkill -f "ollama serve"; sudo systemctl stop ollama 2>/dev/null
OLLAMA_CONTEXT_LENGTH=16384 OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 \
  nohup ollama serve > setup/ollama_server.log 2>&1 &
```

Below 16k, Claude Code may start failing tool calls. If Ollama runs as a systemd service, set these with `sudo systemctl edit ollama` instead (add `Environment="NAME=value"` lines under `[Service]`, then restart it).

**3. Use a smaller model** if `ollama ps` still shows a CPU/GPU split. Rough guide (verify with `ollama ps`):

| VRAM | Starting point |
|---|---|
| CPU only | `qwen3:4b` (slow) |
| ~6GB | 4B model, or `qwen3:8b` with reduced context |
| 8-12GB | `qwen3:8b` or `qwen3.5:9b` |
| 24GB+ | `qwen3-coder:30b` |

**4. Cold starts.** Ollama unloads the model after about 5 minutes idle. Set `OLLAMA_KEEP_ALIVE=30m` to keep it loaded, and judge speed on the second prompt, not the first.

**5. GPU not visible in WSL.** Update the NVIDIA driver on Windows (not inside WSL).

## 3. On a new machine

1. Clone the repo (inside the WSL filesystem if you use WSL).
2. Run `bash setup/bootstrap.sh`. Note that the model menu's default is picked by RAM, not VRAM.
3. Run the three diagnose commands. You want `100% GPU`.
4. Start with `ollama launch claude --model <model>`. Plain `claude` will ask you to log in.