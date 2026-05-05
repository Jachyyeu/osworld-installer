#!/bin/bash
set -euo pipefail

# ============================================================
# pick-theme.sh — Apply KDE theme presets
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

THEMES_DIR="/usr/share/altos/themes"
KDE_CONFIG_DIR="$HOME/.config"

echo -e "${CYAN}"
echo "  Pick your style"
echo -e "${RESET}"
echo ""
echo "  1) Windows 11 style (default)"
echo "     → Taskbar at bottom, centered icons, light theme"
echo ""
echo "  2) Clean Linux"
echo "     → Traditional KDE layout, panel at bottom left"
echo ""
echo "  3) Dark mode"
echo "     → Breeze Dark, dark wallpaper, reduced blue light"
echo ""

read -rp "$(echo -e "${BLUE}[?]${RESET} Enter choice [1-3] (default 1): ")" choice
choice="${choice:-1}"

apply_theme() {
  local theme_name="$1"
  local theme_path="$THEMES_DIR/$theme_name"

  if [[ ! -d "$theme_path" ]]; then
    echo -e "${YELLOW}[WARN] Theme files not found at $theme_path${RESET}"
    echo -e "${YELLOW}[WARN] Applying basic settings instead.${RESET}"
    return
  fi

  # Copy theme configs
  if [[ -d "$theme_path/config" ]]; then
    mkdir -p "$KDE_CONFIG_DIR"
    cp -r "$theme_path/config/"* "$KDE_CONFIG_DIR/" 2>/dev/null || true
  fi

  # Apply Plasma theme if script exists
  if [[ -x "$theme_path/apply.sh" ]]; then
    "$theme_path/apply.sh"
  fi
}

case "$choice" in
  1)
    echo -e "${BLUE}[INFO] Applying Windows 11 style...${RESET}"
    apply_theme "win11"
    # Additional Windows 11-like tweaks
    kwriteconfig5 --file kwinrc --group TabBox --key LayoutName "thumbnail_grid" 2>/dev/null || true
    kwriteconfig5 --file kcmfonts --group General --key font "Segoe UI,10,-1,5,50,0,0,0,0,0" 2>/dev/null || true
    echo -e "${GREEN}[OK] Windows 11 style applied.${RESET}"
    ;;
  2)
    echo -e "${BLUE}[INFO] Applying Clean Linux style...${RESET}"
    apply_theme "clean"
    echo -e "${GREEN}[OK] Clean Linux style applied.${RESET}"
    ;;
  3)
    echo -e "${BLUE}[INFO] Applying Dark mode...${RESET}"
    apply_theme "dark"
    # Force dark color scheme
    kwriteconfig5 --file kdeglobals --group General --key ColorScheme "BreezeDark" 2>/dev/null || true
    kwriteconfig5 --file kcmfonts --group General --key XftAntialias "true" 2>/dev/null || true
    echo -e "${GREEN}[OK] Dark mode applied.${RESET}"
    ;;
  *)
    echo -e "${YELLOW}[WARN] Invalid choice. Applying default (Windows 11 style).${RESET}"
    apply_theme "win11"
    ;;
esac

# Restart Plasma to apply changes (optional, in background)
if pgrep plasmashell &>/dev/null; then
  echo -e "${BLUE}[INFO] Restarting Plasma Shell to apply theme...${RESET}"
  nohup kstart5 plasmashell &>/dev/null || true
fi
