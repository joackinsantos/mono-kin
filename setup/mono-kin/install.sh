#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OLLAMA_HOST_URL="http://localhost:11434"
OPENCHAMBER_EXT="FedaykinDev.openchamber"

export OLLAMA_CONTEXT_LENGTH=65536
export OLLAMA_FLASH_ATTENTION=1
export OLLAMA_KV_CACHE_TYPE=q8_0
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

MODELS=(
  "mimo-v2.6"
  "gpt-oss:20b"
  "qwen3.8:27b"
)

log()  { printf "\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n" "$1"; }
info() { printf "    %s\n" "$1"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$1"; }

ensure_shell_env() {
  local rc_file="$1"
  local add_autostart="${2:-false}"
  touch "$rc_file"

  if ! grep -Fq '.local/bin' "$rc_file"; then
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc_file"
  fi
  if ! grep -Fq '.opencode/bin' "$rc_file"; then
    printf 'export PATH="$HOME/.opencode/bin:$PATH"\n' >> "$rc_file"
  fi
  if ! grep -Fq 'OLLAMA_CONTEXT_LENGTH' "$rc_file"; then
    cat >> "$rc_file" <<'EOF'
export OLLAMA_CONTEXT_LENGTH=65536
export OLLAMA_FLASH_ATTENTION=1
export OLLAMA_KV_CACHE_TYPE=q8_0
EOF
  fi

  if [ "$add_autostart" = "true" ] && ! grep -Fq 'mono-kin: ollama auto-start' "$rc_file"; then
    cat >> "$rc_file" <<'EOF'

# mono-kin: ollama auto-start (fallback when systemd is not active)
if command -v ollama >/dev/null 2>&1 && ! curl -fsS http://localhost:11434/api/tags >/dev/null 2>&1; then
  nohup ollama serve >/tmp/ollama.log 2>&1 &
fi
EOF
  fi
}

wait_for_ollama() {
  for _ in {1..30}; do
    if curl -fsS "${OLLAMA_HOST_URL}/api/tags" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# 1. System prerequisites
log "Checking system prerequisites"
REQUIRED_PKGS=(curl zstd jq git ca-certificates)
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    MISSING_PKGS+=("$pkg")
  fi
done

if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
  info "Installing missing packages: ${MISSING_PKGS[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y -qq "${MISSING_PKGS[@]}"
else
  info "All system prerequisites already installed."
fi

# 2. uv & Python 3.13
log "Checking uv and Python 3.13"
if ! command -v uv >/dev/null 2>&1; then
  info "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

if ! command -v uv >/dev/null 2>&1; then
  warn "uv was not found on PATH after installation."
  exit 1
fi
info "uv verified: $(uv --version)"

uv python install 3.13 >/dev/null
PYTHON_313_PATH="$(uv python find 3.13)"
info "Python 3.13 verified: ${PYTHON_313_PATH}"

# 3. Ollama installation & 64K context service configuration
log "Checking Ollama (64K context)"
if ! command -v ollama >/dev/null 2>&1; then
  info "Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
else
  info "Ollama already installed ($(ollama --version))."
fi

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files ollama.service >/dev/null 2>&1; then
  OVERRIDE_DIR="/etc/systemd/system/ollama.service.d"
  OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"
  TMP_OVERRIDE="$(mktemp)"

  cat > "$TMP_OVERRIDE" <<EOF
[Service]
Environment="OLLAMA_CONTEXT_LENGTH=${OLLAMA_CONTEXT_LENGTH}"
Environment="OLLAMA_FLASH_ATTENTION=${OLLAMA_FLASH_ATTENTION}"
Environment="OLLAMA_KV_CACHE_TYPE=${OLLAMA_KV_CACHE_TYPE}"
EOF

  NEED_RESTART="false"
  if [ ! -f "$OVERRIDE_FILE" ] || ! cmp -s "$TMP_OVERRIDE" "$OVERRIDE_FILE"; then
    info "Configuring systemd override for 64K context..."
    sudo mkdir -p "$OVERRIDE_DIR"
    sudo cp "$TMP_OVERRIDE" "$OVERRIDE_FILE"
    sudo chmod 644 "$OVERRIDE_FILE"
    sudo systemctl daemon-reload
    NEED_RESTART="true"
  fi
  rm -f "$TMP_OVERRIDE"

  if [ "$NEED_RESTART" = "true" ] || ! systemctl is-active --quiet ollama; then
    info "Starting/restarting Ollama systemd service..."
    sudo systemctl enable ollama >/dev/null 2>&1 || true
    sudo systemctl restart ollama
  else
    info "Ollama systemd service already configured with 64K context."
  fi
else
  OLLAMA_PID="$(pgrep -f 'ollama serve' | head -n1 || true)"
  if [ -n "$OLLAMA_PID" ]; then
    if ! tr '\0' '\n' < "/proc/${OLLAMA_PID}/environ" 2>/dev/null | grep -Fxq "OLLAMA_CONTEXT_LENGTH=${OLLAMA_CONTEXT_LENGTH}"; then
      info "Restarting Ollama background process with 64K context..."
      kill "$OLLAMA_PID" 2>/dev/null || true
      sleep 1
    fi
  fi

  if ! curl -fsS "${OLLAMA_HOST_URL}/api/tags" >/dev/null 2>&1; then
    info "Starting Ollama server in background (64K context)..."
    nohup ollama serve >/tmp/ollama.log 2>&1 &
  fi
fi

if ! wait_for_ollama; then
  warn "Ollama did not respond at ${OLLAMA_HOST_URL}. Check /tmp/ollama.log or 'journalctl -u ollama'."
  exit 1
fi
info "Ollama server is running at ${OLLAMA_HOST_URL} (context=${OLLAMA_CONTEXT_LENGTH})."

# 4. Pull local Ollama models
log "Syncing local Ollama models"
INSTALLED_MODELS="$(ollama list 2>/dev/null || true)"

for model in "${MODELS[@]}"; do
  if printf "%s\n" "$INSTALLED_MODELS" | grep -Eq "^${model}(:latest)?[[:space:]]"; then
    info "Model already present: ${model}"
  else
    info "Pulling ${model}..."
    ollama pull "$model"
  fi
done

# 5. OpenCode CLI (v2.x required for OpenChamber)
log "Checking OpenCode (v2.x required for OpenChamber)"
CURRENT_OC_VERSION="0.0.0"
if command -v opencode >/dev/null 2>&1; then
  CURRENT_OC_VERSION="$(opencode --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "0.0.0")"
fi

OC_MAJOR="${CURRENT_OC_VERSION%%.*}"
if [ "$OC_MAJOR" -ge 2 ] 2>/dev/null; then
  info "OpenCode v${CURRENT_OC_VERSION} already installed (v2.x ready)."
else
  if [ "$CURRENT_OC_VERSION" != "0.0.0" ]; then
    info "Upgrading OpenCode v${CURRENT_OC_VERSION} to latest v2.x..."
  else
    info "Installing latest OpenCode v2.x..."
  fi

  curl -fsSL https://opencode.ai/v2/install | bash

  NEW_OC_VERSION="$(opencode --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "0.0.0")"
  NEW_OC_MAJOR="${NEW_OC_VERSION%%.*}"
  if [ "$NEW_OC_MAJOR" -lt 2 ] 2>/dev/null; then
    warn "Expected OpenCode v2.x after V2 install, but found v${NEW_OC_VERSION}."
    exit 1
  fi
  info "OpenCode verified at v${NEW_OC_VERSION}."
fi

# 6. OpenChamber VS Code Extension (WSL Remote)
log "Checking OpenChamber VS Code extension (${OPENCHAMBER_EXT})"
if command -v code >/dev/null 2>&1; then
  if code --list-extensions 2>/dev/null | grep -Fxqi "$OPENCHAMBER_EXT"; then
    info "OpenChamber extension already installed in VS Code."
  else
    info "Installing ${OPENCHAMBER_EXT} into VS Code..."
    code --install-extension "$OPENCHAMBER_EXT"
  fi
else
  warn "'code' CLI not found on PATH; run this script from a VS Code WSL terminal or install '${OPENCHAMBER_EXT}' in the Extensions panel."
fi

# 7. Persist PATH, Ollama 64K env vars, and fallback auto-start
log "Updating shell startup files (~/.bashrc and ~/.profile)"
ensure_shell_env "$HOME/.bashrc" "true"
ensure_shell_env "$HOME/.profile" "false"
info "Shell environment entries verified."

# 8. Validate repo-root opencode.json (V2 schema structure)
log "Validating opencode.json (V2 structure)"
OPENCODE_CONFIG="${REPO_ROOT}/opencode.json"
if [ -f "$OPENCODE_CONFIG" ]; then
  jq -e '
    (.providers | type == "object") and
    (.permissions | type == "array") and
    (.agents | type == "object")
  ' "$OPENCODE_CONFIG" >/dev/null

  for model in "${MODELS[@]}"; do
    if ! jq -e --arg m "$model" '.providers.ollama.models[$m] != null' "$OPENCODE_CONFIG" >/dev/null; then
      warn "Model '${model}' is missing under .providers.ollama.models in ${OPENCODE_CONFIG}."
      exit 1
    fi
  done

  info "Verified valid V2 structure and models at ${OPENCODE_CONFIG}."
else
  warn "No opencode.json found at ${OPENCODE_CONFIG}."
fi

log "Setup complete"
info "Reload VS Code window ('Developer: Reload Window') so OpenChamber connects to OpenCode v2."
