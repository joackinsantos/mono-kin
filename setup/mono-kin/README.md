# `mono-kin` WSL2, OpenCode & OpenChamber Setup

Idempotent bootstrap script and local LLM routing reference for running **OpenCode (`v2.x`)** and the **OpenChamber** VS Code sidebar UI with **Ollama (64K context)** inside WSL2 (Ubuntu).

## Prerequisites

1. **WSL2 Memory Allocation (`.wslconfig` on Windows host):**
   Running 20B–27B models alongside a 64K context window requires sufficient WSL2 memory. Ensure `%UserProfile%\.wslconfig` allocates at least **24 GB RAM** and **8 GB swap** on a 32 GB host:
   ```ini
   [wsl2]
   memory=24GB
   swap=8GB
   ```
2. **VS Code Configs (`vscode/`):**
   Editor settings (`vscode/settings.json`) and the full extension list (`vscode/extensions.txt`) are managed separately in `vscode/` and are not overwritten by `setup/mono-kin/install.sh`.

## Bootstrap

Run from a **VS Code WSL terminal** inside the `mono-kin` repository root (having `code` on `PATH` lets `install.sh` install the OpenChamber VS Code extension automatically):

```bash
chmod +x setup/mono-kin/install.sh
./setup/mono-kin/install.sh
source ~/.bashrc
```

The script is idempotent and safe to re-run at any time. It provisions:

- **System packages:** `curl`, `zstd`, `jq`, `git`, `ca-certificates`
- **Python toolchain:** Installs `uv` and Python `3.13`, verifying both inline
- **Ollama (64K Context):** Installs Ollama if missing, configures `OLLAMA_CONTEXT_LENGTH=65536`, `OLLAMA_FLASH_ATTENTION=1`, and `OLLAMA_KV_CACHE_TYPE=q8_0` (via `systemd` override if active, or background `ollama serve`), and pulls missing models
- **OpenCode CLI (`v2.x`):** Installs or upgrades OpenCode via `https://opencode.ai/v2/install` to match OpenChamber (`2.2.0+`) and the V2 `opencode.json` schema
- **OpenChamber Extension:** Installs `FedaykinDev.openchamber` into VS Code (WSL)
- **Shell Persistence & Auto-Start:** Idempotently adds `PATH` entries, `OLLAMA_*` variables, and an automatic background `ollama serve` fallback to `~/.bashrc` and `~/.profile`
- **Config verification:** Validates the V2 structure and configured models in `opencode.json` at the repository root

## Docking OpenChamber & Multi-Machine Sync

1. **Dock on the right side of VS Code:**
   - Open the **Secondary Side Bar** with **`Ctrl+Alt+B`** (or **View → Appearance → Secondary Side Bar**).
   - Run **`OpenChamber: Open Sidebar`** from the Command Palette (**`Ctrl+Shift+P`**). If it opens in the left Activity Bar, drag its icon onto the right Secondary Side Bar (or run **`View: Move View`** → **OpenChamber** → **Secondary Side Bar**).
   - Toggle the right-hand AI sidebar anytime with **`Ctrl+Alt+B`**.
2. **Syncing across computers:**
   - Ensure **UI State** is enabled under **`Ctrl+Shift+P`** → **`Settings Sync: Configure...`** so VS Code remembers OpenChamber's right-sidebar placement on other machines.
   - Because VS Code Settings Sync does not install extensions inside Remote WSL windows automatically, run `./setup/mono-kin/install.sh` (or `vscode/install.sh`) once in WSL on any new machine.

## After a PC Restart

You **do not** need to re-run `install.sh` or manually start Ollama after rebooting Windows:

1. Open `mono-kin` in VS Code (WSL).
2. Open the **OpenChamber** sidebar on the right (or run `opencode` in a terminal).

Ollama boots automatically in the background with the 64K context window via `systemd` (or via the `~/.bashrc` auto-start hook).

## Verification & Testing

Run this block from the `mono-kin` repository root to test idempotency and verify every component in one pass:

```bash
./setup/mono-kin/install.sh && \
source ~/.bashrc && \
uv --version && \
uv python find 3.13 && \
opencode --version && \
code --list-extensions | grep -i openchamber && \
ollama list && \
curl -fsS http://localhost:11434/api/tags | jq -r '.models[].name' && \
jq -e '(.providers | type == "object") and (.permissions | type == "array") and (.agents | type == "object")' opencode.json >/dev/null && \
echo "opencode.json (V2): OK"
```

### Smoke Test

1. Open the **OpenChamber** sidebar in VS Code (or run `opencode` in the terminal).
2. Confirm all three primary agents (**Build**, **Plan**, **Deep**) appear in the agent selector.
3. Send a test prompt in **Build** to verify local 64K Ollama inference works end-to-end.

## Agent & Model Routing (`opencode.json` — V2 Schema)

All agents use the local `ollama` provider (`@ai-sdk/openai-compatible` at `http://localhost:11434/v1`) with a **65,536-token context limit** and **8,192-token output limit**:

| Agent                           | Model ID         | Role                                                                      |
| :------------------------------ | :--------------- | :------------------------------------------------------------------------ |
| **`build`** _(Build — default)_ | `mimo-v2.6` (9B) | Daily driver for fast implementation, edits, and routine coding tasks     |
| **`plan`** _(Plan)_             | `gpt-oss:20b`    | Architectural planning, system design, specs, and code analysis           |
| **`Deep`** _(custom)_           | `qwen3.8:27b`    | Heavy reasoning for complex refactors, debugging, and visual architecture |
| **`title`** _(background)_      | `mimo-v2.6` (9B) | Automatic session title generation (replaces V1 `small_model`)            |

### Permissions, Sampling & Monorepo Context

- **Permissions:** Configured as a V2 rule array requiring confirmation (`"effect": "ask"`) for both `"edit"` and `"shell"` actions across all resources (`"*"`).
- **Temperature:** Omitted intentionally so Ollama uses each model's calibrated Modelfile default.
- **`AGENTS.md` (optional `/init`):** Running `/init` is optional. For this monorepo, keep any root `AGENTS.md` concise (repo layout and `uv` conventions only) and place detailed instructions in scoped `projects/<name>/AGENTS.md` files so subproject rules load only when needed.
