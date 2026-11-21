#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Install ripgrep in WSL (required at /usr/bin/rg for Todo Tree)
echo "=== 1. Installing ripgrep ==="
sudo apt update
sudo apt install -y ripgrep

# 2. Copy settings.json to Windows VS Code User directory
echo "=== 2. Copying settings.json ==="
WIN_USER_DIR=$(find /mnt/c/Users -maxdepth 1 -mindepth 1 -type d \
  ! -name "Public" ! -name "Default" ! -name "Default User" ! -name "All Users" \
  -exec test -d "{}/AppData/Roaming" \; -print | head -n 1)

if [ -n "$WIN_USER_DIR" ]; then
  TARGET_DIR="$WIN_USER_DIR/AppData/Roaming/Code/User"
  mkdir -p "$TARGET_DIR"
  cp "$SCRIPT_DIR/settings.json" "$TARGET_DIR/settings.json"
  echo "Copied settings.json -> $TARGET_DIR/settings.json"
else
  echo "Windows AppData directory not found; skipping settings.json copy."
fi

# 3. Install all VS Code extensions
echo "=== 3. Installing VS Code Extensions ==="
if command -v code >/dev/null 2>&1; then
  while IFS= read -r ext || [ -n "$ext" ]; do
    [ -z "$ext" ] && continue
    code --install-extension "$ext" --force
  done < "$SCRIPT_DIR/extensions.txt"
  echo "Done! VS Code setup complete."
else
  echo "'code' CLI not found in PATH. Open VS Code once from WSL and re-run."
  exit 1
fi
