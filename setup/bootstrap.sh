#!/usr/bin/env bash
# Portable setup: Claude Code + Ollama (Qwen/Devstral) + uv
# Usage: ./setup/bootstrap.sh [--update] [--model <model>[,<model>...]|all] [--skip-test]

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p setup

OLLAMA_URL="http://localhost:11434"
UPDATE=0; SKIP_TEST=0; MODEL_ARG=""

# Ordered lightweight -> heavy. Sizes are approximate downloads in GB.
ALL_MODELS=("qwen3:8b" "qwen3.5:9b" "devstral:24b" "qwen3.6:27b" "qwen3.8:27b" "qwen3-coder:30b")
ALL_SIZES=(5 7 14 17 18 19)

while [ $# -gt 0 ]; do
    case "$1" in
        --update)    UPDATE=1 ;;
        --skip-test) SKIP_TEST=1 ;;
        --model)     MODEL_ARG="${2:-}"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

OS="$(uname -s)"
export PATH="$HOME/.local/bin:$PATH"

have() { command -v "$1" >/dev/null 2>&1; }
ollama_up() { curl -sf "$OLLAMA_URL" >/dev/null 2>&1; }
is_windows_bin() { [[ "$(command -v "$1" 2>/dev/null)" == /mnt/* ]]; }

echo "🚀 Starting Setup (OS: $OS)..."

# ---------- 1. Claude Code (native installer, WSL-safe) ----------
if ! have claude || is_windows_bin claude; then
    is_windows_bin claude && echo "⚠️  'claude' currently resolves to Windows ($(command -v claude)). Installing a Linux copy..."
    echo "🤖 Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash || { echo "❌ Claude Code install failed"; exit 1; }
elif [ "$UPDATE" = 1 ]; then
    echo "🤖 Updating Claude Code..."
    claude update || true
else
    echo "🤖 Claude Code already installed ($(claude --version 2>/dev/null))"
fi

# Make sure the Linux binary wins in future shells
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ] && ! grep -q '>>> claude-code-path >>>' "$rc"; then
        printf '\n# >>> claude-code-path >>>\nexport PATH="$HOME/.local/bin:$PATH"\n# <<< claude-code-path <<<\n' >> "$rc"
    fi
done
export PATH="$HOME/.local/bin:$PATH"
hash -r

# Verify we're now using the Linux binary
if ! have claude || is_windows_bin claude; then
    echo "❌ 'claude' still resolves to: $(command -v claude || echo 'nothing')"
    echo "   Expected ~/.local/bin/claude. Check your PATH."
    exit 1
fi
echo "✅ Using Linux Claude Code at $(command -v claude)"

# ---------- 2. Ollama ----------
if ! have ollama; then
    echo "🦙 Installing Ollama..."
    if [ "$OS" = "Darwin" ]; then
        if have brew; then brew install ollama
        else echo "❌ Install Ollama from https://ollama.com/download and rerun."; exit 1; fi
    else
        curl -fsSL https://ollama.com/install.sh | sh || { echo "❌ Ollama install failed"; exit 1; }
    fi
elif [ "$UPDATE" = 1 ] && [ "$OS" = "Linux" ]; then
    echo "🦙 Updating Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "🦙 Ollama already installed ($(ollama --version 2>/dev/null | tail -n1))"
fi

# ---------- 3. uv ----------
if ! have uv; then
    echo "⚡ Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
elif [ "$UPDATE" = 1 ]; then
    uv self update || true
fi

# ---------- 4. Python environment ----------
echo "🐍 Syncing Python environment..."
[ ! -d "agent" ] && uv init agent
(cd agent && uv sync)

# ---------- 5. Hardware detection ----------
if [ "$OS" = "Darwin" ]; then
    RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
else
    RAM_GB=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 ))
fi

VRAM_GB=0
if [ "$OS" != "Darwin" ] && have nvidia-smi; then
    VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' ')
    [[ "$VRAM_MB" =~ ^[0-9]+$ ]] && VRAM_GB=$(( VRAM_MB / 1024 ))
fi

# Memory the model can realistically use: GPU VRAM if present, else RAM (unified memory on Mac)
if [ "$VRAM_GB" -gt 0 ]; then BUDGET_GB=$VRAM_GB; else BUDGET_GB=$RAM_GB; fi

if   [ "$BUDGET_GB" -ge 48 ]; then DEFAULT=4
elif [ "$BUDGET_GB" -ge 24 ]; then DEFAULT=3
elif [ "$BUDGET_GB" -ge 12 ]; then DEFAULT=2
else DEFAULT=1; fi
RECOMMENDED="${ALL_MODELS[$((DEFAULT-1))]}"

# Claude Code needs a big context; go smaller only on low-memory machines
if [ -n "${OLLAMA_CONTEXT_LENGTH:-}" ]; then CTX_LEN="$OLLAMA_CONTEXT_LENGTH"
elif [ "$BUDGET_GB" -lt 12 ]; then CTX_LEN=16384
else CTX_LEN=32768; fi

echo "🖥️  Detected: ${RAM_GB}GB RAM, ${VRAM_GB}GB VRAM (using ${BUDGET_GB}GB as the model budget)"

# ---------- 6. Ollama server ----------
if ollama_up; then
    echo "🦙 Ollama server already running."
    echo "   ⚠️  If it was started as a service, it may not use a ${CTX_LEN} context."
    echo "      Linux/systemd fix: sudo systemctl edit ollama  → add"
    echo "      [Service]"
    echo "      Environment=\"OLLAMA_CONTEXT_LENGTH=${CTX_LEN}\""
    echo "      Environment=\"OLLAMA_FLASH_ATTENTION=1\""
    echo "      Environment=\"OLLAMA_KV_CACHE_TYPE=q8_0\""
    echo "      then: sudo systemctl restart ollama"
else
    echo "⏳ Starting Ollama server (context: $CTX_LEN)..."
    OLLAMA_CONTEXT_LENGTH="$CTX_LEN" OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 \
        nohup ollama serve > setup/ollama_server.log 2>&1 &
    for _ in $(seq 1 30); do ollama_up && break; sleep 1; done
    ollama_up || { echo "❌ Ollama didn't start. See setup/ollama_server.log"; exit 1; }
fi

# ---------- 7. Pick + pull models ----------
MODELS=()

if [ -n "$MODEL_ARG" ]; then
    if [ "$MODEL_ARG" = "all" ]; then
        MODELS=("${ALL_MODELS[@]}")
    else
        IFS=',' read -r -a MODELS <<< "$MODEL_ARG"
    fi
else
    echo -e "\n🧠 Select models to install/update (sizes are approximate downloads):"
    echo ""
    echo "Lightweight  (~6-8GB VRAM, or 8-16GB RAM)"
    echo "  1) qwen3:8b          ~5GB   general purpose, weaker tool use"
    echo "  2) qwen3.5:9b        ~7GB   newer lightweight"
    echo "Mid-size     (~16-24GB VRAM or unified memory)"
    echo "  3) devstral:24b      ~14GB  agentic coding specialist (new, untested)"
    echo "High-end     (~24-32GB+)"
    echo "  4) qwen3.6:27b       ~17GB  newer Qwen coder (new, untested)"
    echo "  5) qwen3.8:27b       ~18GB  newest Qwen (new, untested)"
    echo "  6) qwen3-coder:30b   ~19GB  coding-tuned, long context"
    echo ""
    echo "  7) All lightweight (1 and 2)"
    echo "  8) Everything (~80GB download)"
    echo ""
    echo "Pick one or several, e.g. '3' or '1,3'."
    read -r -p "Choice [default $DEFAULT]: " choice
    choice="${choice:-$DEFAULT}"

    SEL_IDX=()
    for tok in ${choice//,/ }; do
        case "$tok" in
            1|2|3|4|5|6) SEL_IDX+=("$tok") ;;
            7) SEL_IDX+=(1 2) ;;
            8) SEL_IDX+=(1 2 3 4 5 6) ;;
            *) echo "Invalid choice: $tok"; exit 1 ;;
        esac
    done

    # Rebuild in light -> heavy order, no duplicates
    for i in 1 2 3 4 5 6; do
        for s in "${SEL_IDX[@]}"; do
            if [ "$s" = "$i" ]; then MODELS+=("${ALL_MODELS[$((i-1))]}"); break; fi
        done
    done

    if [ "${#MODELS[@]}" -ge 5 ]; then
        read -r -p "That's a large download. Continue? [y/N]: " yn
        [[ "$yn" =~ ^[Yy]$ ]] || { echo "Aborting."; exit 1; }
    fi
fi

# Warn about models that won't fully fit
for m in "${MODELS[@]}"; do
    for i in 0 1 2 3 4 5; do
        if [ "${ALL_MODELS[$i]}" = "$m" ] && [ "${ALL_SIZES[$i]}" -gt "$BUDGET_GB" ]; then
            echo "⚠️  $m (~${ALL_SIZES[$i]}GB) is larger than your ~${BUDGET_GB}GB budget: expect CPU offload and slow responses."
        fi
    done
done

PULLED=(); FAILED=()
for m in "${MODELS[@]}"; do
    echo "📥 Pulling $m..."
    if ollama pull "$m"; then PULLED+=("$m"); else FAILED+=("$m"); fi
done

if [ "${#PULLED[@]}" -gt 0 ]; then
    # Track pulled models so teardown knows what to offer to remove
    printf '%s\n' "${PULLED[@]}" >> setup/.models
    sort -u setup/.models -o setup/.models
fi
if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "⚠️  Failed to pull: ${FAILED[*]}"
fi
if [ "${#PULLED[@]}" -eq 0 ]; then
    echo "❌ No models were installed, so Claude Code can't be tested."
    exit 1
fi

# Test model: the recommended one if installed, otherwise the lightest one installed
TEST_MODEL="${PULLED[0]}"
for m in "${PULLED[@]}"; do
    [ "$m" = "$RECOMMENDED" ] && TEST_MODEL="$m"
done

# ---------- 8. Smoke test ----------
if [ "$SKIP_TEST" = 0 ]; then
    echo "🧪 Smoke test: Claude Code → Ollama → $TEST_MODEL ..."
    if ollama launch claude --model "$TEST_MODEL" --yes -- -p "Reply with exactly: OK"; then
        echo "✅ Claude Code is talking to $TEST_MODEL"
    else
        echo "❌ Smoke test failed. Try manually: ollama launch claude --model $TEST_MODEL"
        echo "   Also check: ollama --version (launch needs a recent version; run with --update)"
        exit 1
    fi
fi

echo -e "\n🎉 Setup complete!"
echo "Open a new terminal (or run: source ~/.bashrc) so PATH changes apply, then start with:"
echo "   ollama launch claude --model $TEST_MODEL"
echo "Inside Claude Code, run /status to confirm the connection."
[ "${#PULLED[@]}" -gt 1 ] && echo "Installed models: ${PULLED[*]}"
exit 0