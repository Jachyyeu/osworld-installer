#!/bin/bash
set -euo pipefail

# ============================================================
# restore-snapshot.sh — Rollback to a previous BTRFS snapshot
# ============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

find_altos_root() {
  lsblk -rno NAME,FSTYPE,LABEL,PARTLABEL 2>/dev/null | awk '$2=="btrfs" && ($4=="Linux Root" || $3=="Linux Root") {print "/dev/" $1}' | head -n1
}

ALTOS_ROOT=$(find_altos_root)
MOUNT_POINT="/mnt/rescue"

if [[ -z "$ALTOS_ROOT" ]]; then
  echo -e "${RED}[FAIL] No AltOS root partition found.${RESET}"
  exit 1
fi

echo -e "${BLUE}[INFO] Mounting $ALTOS_ROOT...${RESET}"
mkdir -p "$MOUNT_POINT"
mount "$ALTOS_ROOT" "$MOUNT_POINT"

# Check if snapper is available
if ! command -v snapper &>/dev/null; then
  echo -e "${YELLOW}[WARN] snapper not found. Trying btrfs subvolume list instead...${RESET}"
  echo ""
  echo -e "${BLUE}Available subvolumes:${RESET}"
  btrfs subvolume list "$MOUNT_POINT" || true
  umount "$MOUNT_POINT" || true
  exit 0
fi

echo ""
echo -e "${BLUE}[INFO] Available snapshots:${RESET}"
snapper -c root list || true

echo ""
read -rp "$(echo -e "${BLUE}[?]${RESET} Enter snapshot number to rollback to: ")" snap_num

if [[ -z "$snap_num" ]]; then
  echo -e "${YELLOW}[SKIP] No snapshot selected.${RESET}"
  umount "$MOUNT_POINT" || true
  exit 0
fi

echo -e "${YELLOW}[WARN] About to rollback to snapshot $snap_num.${RESET}"
echo -e "${YELLOW}[WARN] Current system state will be lost unless a snapshot was made.${RESET}"
read -rp "$(echo -e "${RED}[!]${RESET} Type ROLLBACK to confirm: ")" confirm

if [[ "$confirm" != "ROLLBACK" ]]; then
  echo -e "${YELLOW}[SKIP] Cancelled.${RESET}"
  umount "$MOUNT_POINT" || true
  exit 0
fi

# Perform rollback
snapper -c root rollback "$snap_num" || true

echo -e "${GREEN}[OK] Rollback to snapshot $snap_num complete.${RESET}"

umount "$MOUNT_POINT" || true

echo ""
read -rp "$(echo -e "${BLUE}[?]${RESET} Reboot now? [y/N]: ")" answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  reboot
fi
