#!/usr/bin/env bash
# Teardown for the Claude Code + Ollama bootstrap.
# Removes only what bootstrap.sh created. Leaves Ollama, uv, Node/nvm installed.
# Usage: ./setup/teardown.sh [--yes]

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

have() { command -v "$1" >/dev/null 2>&1; }
ask() {  # ask "question" -> returns 0 if yes (auto-yes with --yes)
    [ "${ASSUME_YES:-0}" = 1 ] && return 0
    read -r -p "$1 (y/n) " -n 1 REPLY; echo ""
    [[ "$REPLY" =~ ^[Yy]$ ]]
}

[ "${1:-}" = "--yes" ] && ASSUME_YES=1

echo "🧹 Starting safe teardown..."
ask "This will delete agent/, setup logs, and remove Claude Code. Proceed?" || { echo "Aborting."; exit 1; }

# 1. Isolated Python project
if [ -d "agent" ]; then
    echo "🗑️  Removing agent/ and its virtual environment..."
    rm -rf agent
else
    echo "⏭️  No agent/ folder found. Skipping."
fi

# 2. Read the models bootstrap pulled (before deleting the tracking files)
MODELS=()
for f in setup/.models setup/.model; do   # .model = older single-model file
    [ -f "$f" ] || continue
    while IFS= read -r line; do
        [ -n "$line" ] && MODELS+=("$line")
    done < "$f"
done
rm -f setup/.models setup/.model setup/ollama_server.log

# 3. Claude Code
#    Native install: binary/symlink in ~/.local/bin, data in ~/.local/share/claude
if [ -e "$HOME/.local/bin/claude" ] || [ -L "$HOME/.local/bin/claude" ] || [ -d "$HOME/.local/share/claude" ]; then
    echo "🗑️  Removing native Claude Code install..."
    rm -f "$HOME/.local/bin/claude"
    rm -rf "$HOME/.local/share/claude"
else
    echo "⏭️  No native Claude Code install found."
fi

#    Legacy npm install (from the old bootstrap), only if present
if have npm && [[ "$(command -v npm)" != /mnt/* ]] && npm ls -g --depth=0 @anthropic-ai/claude-code >/dev/null 2>&1; then
    echo "🗑️  Removing legacy npm Claude Code package..."
    npm uninstall -g @anthropic-ai/claude-code
fi

# 4. Shell profile cleanup
echo "🗑️  Cleaning Claude Code lines from profile files..."
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue

    # 4a. Remove the marker-delimited PATH block written by bootstrap.sh
    tmp="$(mktemp)"
    awk '/# >>> claude-code-path >>>/{skip=1} !skip{print} /# <<< claude-code-path <<</{skip=0}' "$rc" > "$tmp" \
        && cat "$tmp" > "$rc"
    rm -f "$tmp"

    # 4b. Remove legacy routing variables (old bootstrap / manual setup)
    tmp="$(mktemp)"
    grep -v -E '^# Claude Code Local Routing|^export ANTHROPIC_BASE_URL="http://localhost:11434"|^export ANTHROPIC_AUTH_TOKEN="ollama"|^export ANTHROPIC_API_KEY=""|^export ANTHROPIC_MODEL=|^export ANTHROPIC_SMALL_FAST_MODEL=|^export OLLAMA_CONTEXT_LENGTH=' "$rc" > "$tmp" \
        && cat "$tmp" > "$rc"
    rm -f "$tmp"
done

# 5. Optional: Claude Code login/config state (global, so it asks first)
if [ -e "$HOME/.claude" ] || [ -e "$HOME/.claude.json" ]; then
    if ask "Also delete Claude Code settings/login state (~/.claude, ~/.claude.json) for a truly fresh start?"; then
        rm -rf "$HOME/.claude" "$HOME/.claude.json"
        echo "🗑️  Removed Claude Code config."
    else
        echo "⏭️  Keeping Claude Code config."
    fi
fi

# 6. Optional: the pulled Ollama models (large, and may be shared with other projects)
if [ "${#MODELS[@]}" -gt 0 ] && have ollama && ollama list >/dev/null 2>&1; then
    if ask "Remove Ollama models bootstrap pulled (${MODELS[*]})? Frees disk space; re-download needed later."; then
        for m in "${MODELS[@]}"; do
            ollama list 2>/dev/null | grep -q "^$m" && ollama rm "$m"
        done
    else
        echo "⏭️  Keeping models."
    fi
fi

echo "✅ Teardown complete."
echo "   Left untouched: Ollama, uv, Node/nvm (and any running Ollama server)."
echo "   Open a new terminal so shell changes take effect, then run ./setup/bootstrap.sh"