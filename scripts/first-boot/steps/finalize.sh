#!/bin/bash
set -euo pipefail

# ============================================================
# finalize.sh — Create first-boot-done flag and finish
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

DONE_FLAG="$HOME/.config/altos/first-boot-done"

mkdir -p "$(dirname "$DONE_FLAG")"
touch "$DONE_FLAG"

echo -e "${GREEN}[OK] First-boot flag created.${RESET}"

echo ""
echo -e "${CYAN}=======================================${RESET}"
echo -e "${CYAN}  Setup complete!${RESET}"
echo -e "${CYAN}=======================================${RESET}"
echo ""
echo -e "${BLUE}Your AltOS system is ready to use.${RESET}"
echo ""

read -rp "$(echo -e "${BLUE}[?]${RESET} Reboot now? [y/N]: ")" answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  echo -e "${BLUE}[INFO] Rebooting in 5 seconds...${RESET}"
  sleep 5
  sudo reboot
else
  echo -e "${BLUE}[INFO] You can reboot later using: sudo reboot${RESET}"
fi
