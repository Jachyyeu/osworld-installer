#!/bin/bash
set -euo pipefail

# ============================================================
# recovery.sh — AltOS Rescue Environment Main Menu
# Runs inside Arch Live/rescue environment.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors -------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

print_banner() {
  clear
  echo -e "${RED}"
  echo '  ___  ____   _____ ____  ___   ____ ___  __'
  echo ' / _ \|  _ \ / ____|___ \/ _ \ / ___/ _ \/_ |'
  echo '| | | | |_) | |      __) | | | | |  | | | || |'
  echo '| |_| |  _ <| |___  / __/| |_| | |__| |_| || |'
  echo ' \___/|_| \_\\_____||_____|\___/ \____\___/ |_|'
  echo -e "${RESET}"
  echo -e "${YELLOW}=======================================${RESET}"
  echo -e "${YELLOW}  AltOS Recovery Mode${RESET}"
  echo -e "${YELLOW}=======================================${RESET}"
  echo ""
}

# Detect installed AltOS system
find_altos_root() {
  lsblk -rno NAME,FSTYPE,LABEL,PARTLABEL 2>/dev/null | awk '$2=="btrfs" && ($4=="Linux Root" || $3=="Linux Root") {print "/dev/" $1}' | head -n1
}

MOUNT_POINT="/mnt/rescue"
ALTOS_ROOT=$(find_altos_root)

print_banner

if [[ -z "$ALTOS_ROOT" ]]; then
  echo -e "${RED}[FAIL] Could not find AltOS root partition (btrfs with label 'Linux Root').${RESET}"
  echo -e "${YELLOW}[WARN] This may mean AltOS was not installed, or the partition label is missing.${RESET}"
  echo ""
fi

if [[ -n "$ALTOS_ROOT" ]]; then
  echo -e "${GREEN}[OK] Found AltOS root: $ALTOS_ROOT${RESET}"
  mkdir -p "$MOUNT_POINT"
  if mount -o ro "$ALTOS_ROOT" "$MOUNT_POINT" 2>/dev/null; then
    echo -e "${GREEN}[OK] Mounted read-only at $MOUNT_POINT${RESET}"
  else
    echo -e "${YELLOW}[WARN] Could not mount AltOS root (may be corrupted).${RESET}"
    ALTOS_ROOT=""
  fi
fi

echo ""
echo -e "${CYAN}Choose an option:${RESET}"
echo ""
echo "  [1] Boot Windows instead"
echo "  [2] Restore last working snapshot (BTRFS snapper rollback)"
echo "  [3] Reinstall bootloader (GRUB + os-prober)"
echo "  [4] Check and repair filesystem (btrfs check)"
echo "  [5] Reinstall NVIDIA drivers (if black screen suspected)"
echo "  [6] Open terminal (manual repair)"
echo "  [7] Launch uninstaller (remove AltOS completely)"
echo ""

read -rp "$(echo -e "${BLUE}[?]${RESET} Enter choice [1-7]: ")" choice

case "$choice" in
  1)
    echo -e "${BLUE}[INFO] Booting Windows...${RESET}"
    "$SCRIPT_DIR/windows-rescue.sh"
    ;;
  2)
    echo -e "${BLUE}[INFO] Restoring snapshot...${RESET}"
    "$SCRIPT_DIR/restore-snapshot.sh"
    ;;
  3)
    echo -e "${BLUE}[INFO] Reinstalling bootloader...${RESET}"
    "$SCRIPT_DIR/reinstall-bootloader.sh"
    ;;
  4)
    echo -e "${BLUE}[INFO] Checking filesystem...${RESET}"
    if [[ -n "$ALTOS_ROOT" ]]; then
      umount "$MOUNT_POINT" 2>/dev/null || true
      echo -e "${YELLOW}[WARN] Running btrfs check --repair on $ALTOS_ROOT${RESET}"
      echo -e "${YELLOW}[WARN] A snapshot will be created first if possible.${RESET}"
      read -rp "$(echo -e "${RED}[!]${RESET} This is potentially destructive. Type REPAIR to continue: ")" confirm
      if [[ "$confirm" == "REPAIR" ]]; then
        btrfs check --repair "$ALTOS_ROOT" || true
        echo -e "${GREEN}[OK] Filesystem check complete.${RESET}"
      else
        echo -e "${YELLOW}[SKIP] Cancelled.${RESET}"
      fi
      mount -o ro "$ALTOS_ROOT" "$MOUNT_POINT" 2>/dev/null || true
    else
      echo -e "${RED}[FAIL] No AltOS root found to check.${RESET}"
    fi
    ;;
  5)
    echo -e "${BLUE}[INFO] Reinstalling NVIDIA drivers...${RESET}"
    if [[ -n "$ALTOS_ROOT" ]]; then
      umount "$MOUNT_POINT" 2>/dev/null || true
      mount "$ALTOS_ROOT" "$MOUNT_POINT" 2>/dev/null || true
      arch-chroot "$MOUNT_POINT" pacman -S --noconfirm nvidia-dkms nvidia-utils || true
      arch-chroot "$MOUNT_POINT" mkinitcpio -P || true
      umount "$MOUNT_POINT" || true
      echo -e "${GREEN}[OK] NVIDIA drivers reinstalled. Reboot to test.${RESET}"
    else
      echo -e "${RED}[FAIL] No AltOS root found.${RESET}"
    fi
    ;;
  6)
    echo -e "${BLUE}[INFO] Opening rescue terminal...${RESET}"
    echo -e "${YELLOW}[WARN] You are in the rescue environment. Be careful.${RESET}"
    echo -e "${BLUE}[INFO] AltOS root (if found) is at: $MOUNT_POINT${RESET}"
    echo -e "${BLUE}[INFO] Run '$SCRIPT_DIR/diagnose.sh' to generate a report.${RESET}"
    /bin/bash
    ;;
  7)
    echo -e "${RED}[WARN] This will completely remove AltOS.${RESET}"
    read -rp "$(echo -e "${RED}[!]${RESET} Type REMOVE to confirm: ")" confirm
    if [[ "$confirm" == "REMOVE" ]]; then
      "$SCRIPT_DIR/../uninstaller/uninstall.sh"
    else
      echo -e "${YELLOW}[SKIP] Cancelled.${RESET}"
    fi
    ;;
  *)
    echo -e "${YELLOW}[WARN] Invalid choice. Exiting to shell.${RESET}"
    /bin/bash
    ;;
esac
