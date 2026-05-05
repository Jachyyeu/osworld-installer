#!/bin/bash
set -euo pipefail

# ============================================================
# setup-apps.sh — Install recommended applications
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
RESET='\033[0m'

apps_to_install=()

ask_app() {
  local name="$1"
  local pkg="$2"
  local answer
  read -rp "$(echo -e "${BLUE}[?]${RESET} Install $name? [y/N]: ")" answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    apps_to_install+=("$name|$pkg")
  fi
}

echo -e "${BLUE}[INFO] Choose recommended apps to install:${RESET}"
echo ""

ask_app "Steam"       "steam"
ask_app "Discord"     "discord"
ask_app "Spotify"     "spotify-launcher"
ask_app "VS Code"     "code"

if [[ ${#apps_to_install[@]} -eq 0 ]]; then
  echo -e "${YELLOW}[SKIP] No apps selected.${RESET}"
  exit 0
fi

echo ""
echo -e "${BLUE}[INFO] Installing selected apps...${RESET}"

for item in "${apps_to_install[@]}"; do
  name="${item%%|*}"
  pkg="${item#*|}"

  echo -e "${BLUE}[INFO] Installing $name ($pkg)...${RESET}"

  # Try pacman first (official repos / AUR helper)
  if pacman -Qi "$pkg" &>/dev/null; then
    echo -e "${GREEN}[OK] $name is already installed.${RESET}"
    continue
  fi

  # Try with pacman (official repo)
  if pacman -Si "$pkg" &>/dev/null; then
    if sudo pacman -S --noconfirm --needed "$pkg" 2>/dev/null; then
      echo -e "${GREEN}[OK] $name installed via pacman.${RESET}"
      continue
    fi
  fi

  # Try flatpak as fallback
  if command -v flatpak &>/dev/null; then
    flatpak_ref=""
    case "$pkg" in
      steam) flatpak_ref="com.valvesoftware.Steam" ;;
      discord) flatpak_ref="com.discordapp.Discord" ;;
      spotify-launcher) flatpak_ref="com.spotify.Client" ;;
      code) flatpak_ref="com.visualstudio.code" ;;
    esac

    if [[ -n "$flatpak_ref" ]]; then
      if flatpak install --noninteractive flathub "$flatpak_ref" 2>/dev/null; then
        echo -e "${GREEN}[OK] $name installed via flatpak.${RESET}"
        continue
      fi
    fi
  fi

  echo -e "${YELLOW}[WARN] Could not install $name automatically.${RESET}"
  echo -e "${YELLOW}[WARN] You may need to install it manually later.${RESET}"
done

echo ""
echo -e "${GREEN}[OK] App installation step complete.${RESET}"
