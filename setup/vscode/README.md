# VS Code Environment Setup

Guide and scripts to reproduce this VS Code setup on a fresh Windows + WSL Ubuntu laptop.

---

## 1. Install Fonts on Windows

Download and install both font families into Windows Fonts:

- **Google Sans** (for Markdown editor & preview): https://fonts.google.com/specimen/Google+Sans
- **JetBrains Mono** (for code editor & integrated terminal): https://fonts.google.com/specimen/JetBrains+Mono

Extract both downloaded `.zip` archives, select the `.ttf` font files, right-click, and choose **Install** (or drag them into **Windows Settings -> Personalization -> Fonts**).

---

## 2. Enable VS Code Settings Sync

1. Open VS Code, click the **Manage gear icon** (bottom-left), and select **Turn on Settings Sync...** (or **Backup and Sync Settings...**).
2. Sign in with your **GitHub** account to sync your settings, keybindings, UI state, and local extensions.

_(Note: VS Code Settings Sync does not automatically sync extensions inside a WSL remote window, so run the bootstrap script below on any new WSL setup.)_

---

## 3. Run the VS Code Bootstrap Script (WSL)

From the `mono-kin` repo root, run:

    chmod +x setup/vscode/install.sh
    ./setup/vscode/install.sh

This script:

1. Installs `ripgrep` (`/usr/bin/rg`) in WSL for the **Todo Tree** extension.
2. Copies `setup/vscode/settings.json` to your Windows VS Code User folder.
3. Installs every extension listed in `setup/vscode/extensions.txt` into WSL.

Verify:

    which rg && code --list-extensions

---

## 4. Import VS Code Pets (`setup/vscode/pet.json`)

Active pets are stored per workspace folder rather than globally. To load your saved pets into any new folder:

1. Open the Command Palette (`Ctrl + Shift + P`) and run **Start pet coding session** (`vscode-pets.start`).
2. Open the Command Palette (`Ctrl + Shift + P`) again, run **Import pet list** (`vscode-pets.import-pets`), and select `setup/vscode/pet.json`.

---

## 5. Maintenance Commands (Updating This Repo Snapshot)

Whenever you change `settings.json`, install/uninstall extensions, or update your pets, update the saved files in `setup/vscode/` before committing:

    # Export updated settings.json
    cp /mnt/c/Users/*/AppData/Roaming/Code/User/settings.json setup/vscode/settings.json

    # Export updated WSL extensions list
    code --list-extensions > setup/vscode/extensions.txt

- **Update `pet.json`:** Open the Command Palette (`Ctrl + Shift + P`), run **Export pet list** (`vscode-pets.export-pets`), and overwrite `setup/vscode/pet.json`.
