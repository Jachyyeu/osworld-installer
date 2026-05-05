#!/bin/bash
set -euo pipefail

# ============================================================
# windows-rescue.sh — Temporarily boot into Windows
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo -e "${BLUE}[INFO] Setting Windows Boot Manager as next boot entry...${RESET}"

if ! command -v efibootmgr &>/dev/null; then
  echo -e "${RED}[FAIL] efibootmgr not available.${RESET}"
  exit 1
fi

# Find Windows Boot Manager entry
WIN_BOOTNUM=$(efibootmgr | grep -i "windows" | head -n1 | sed 's/Boot\([0-9A-Fa-f]*\).*/\1/')

if [[ -z "$WIN_BOOTNUM" ]]; then
  echo -e "${YELLOW}[WARN] Windows Boot Manager not found in efibootmgr.${RESET}"
  echo -e "${YELLOW}[WARN] Available entries:${RESET}"
  efibootmgr
  echo ""
  read -rp "$(echo -e "${BLUE}[?]${RESET} Enter Windows boot number manually: ")" manual_num
  WIN_BOOTNUM="$manual_num"
fi

if [[ -n "$WIN_BOOTNUM" ]]; then
  efibootmgr -n "$WIN_BOOTNUM" 2>/dev/null || true
  echo -e "${GREEN}[OK] Windows Boot Manager set as next boot (one time).${RESET}"
else
  echo -e "${RED}[FAIL] Could not set Windows as next boot.${RESET}"
  exit 1
fi

echo ""
echo -e "${BLUE}[INFO] Rebooting into Windows...${RESET}"
sleep 3
reboot
