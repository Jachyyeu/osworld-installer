#!/bin/bash
set -euo pipefail

# ============================================================
# uninstall.sh — Linux-side rescue uninstaller for AltOS
# Removes AltOS partitions and restores Windows Boot Manager.
# Run from a Linux Live USB if Windows won't boot.
# ============================================================

LOG_FILE="/tmp/altos-uninstall.log"

# --- Colors -------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

log() {
  local msg="$1"
  echo -e "$msg"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$LOG_FILE"
}

# --- Safety -------------------------------------------------
echo -e "${RED}=======================================${RESET}"
echo -e "${RED}  ALTOS RESCUE UNINSTALLER${RESET}"
echo -e "${RED}=======================================${RESET}"
echo ""
echo -e "${YELLOW}This will REMOVE AltOS partitions and restore Windows Boot Manager.${RESET}"
echo -e "${YELLOW}Your Windows data will be preserved.${RESET}"
echo ""
echo -e "${RED}Type REMOVE to confirm, or anything else to abort:${RESET}"
read -rp "> " CONFIRM

if [[ "$CONFIRM" != "REMOVE" ]]; then
  echo -e "${BLUE}[INFO] Uninstall cancelled.${RESET}"
  exit 0
fi

# Must be root
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${RED}[FAIL] This script must be run as root (use sudo).${RESET}"
  exit 1
fi

# --- Detect AltOS partitions --------------------------------
log "${BLUE}[INFO] Scanning for AltOS partitions...${RESET}"

# Find partitions labeled as AltOS
ALTOS_ROOT=$(lsblk -rno NAME,PARTLABEL 2>/dev/null | awk '$2=="Linux Root" {print "/dev/" $1}' | head -n1)
ALTOS_HOME=$(lsblk -rno NAME,PARTLABEL 2>/dev/null | awk '$2=="Linux Home" {print "/dev/" $1}' | head -n1)
OSWORLDBOOT=$(lsblk -rno NAME,LABEL 2>/dev/null | awk '$2=="OSWORLDBOOT" {print "/dev/" $1}' | head -n1)

log "${GREEN}[OK] Root: ${ALTOS_ROOT:-<not found>}${RESET}"
log "${GREEN}[OK] Home: ${ALTOS_HOME:-<not found>}${RESET}"
log "${GREEN}[OK] Boot: ${OSWORLDBOOT:-<not found>}${RESET}"

if [[ -z "$ALTOS_ROOT" && -z "$ALTOS_HOME" && -z "$OSWORLDBOOT" ]]; then
  log "${YELLOW}[WARN] No AltOS partitions found. Nothing to remove.${RESET}"
  exit 0
fi

# Find the parent disk for partition deletion
find_parent_disk() {
  local part="$1"
  lsblk -rno PKNAME "$part" 2>/dev/null | head -n1
}

# --- Unmount if mounted -------------------------------------
for part in "$ALTOS_ROOT" "$ALTOS_HOME" "$OSWORLDBOOT"; do
  if [[ -n "$part" ]]; then
    if mountpoint -q "$part" 2>/dev/null; then
      log "${YELLOW}[WARN] Unmounting $part...${RESET}"
      umount "$part" || true
    fi
  fi
done

# --- Remove partitions --------------------------------------
remove_partition() {
  local part="$1"
  local disk
  local partnum

  disk="/dev/$(find_parent_disk "$part")"
  partnum=$(echo "$part" | grep -o '[0-9]*$')

  if [[ -z "$disk" || -z "$partnum" ]]; then
    log "${YELLOW}[WARN] Could not determine disk/partition number for $part${RESET}"
    return 1
  fi

  log "${BLUE}[INFO] Removing partition $part from $disk...${RESET}"
  parted -s "$disk" rm "$partnum" || sgdisk -d "$partnum" "$disk" || true
  log "${GREEN}[OK] Removed $part${RESET}"
}

if [[ -n "$OSWORLDBOOT" ]]; then
  remove_partition "$OSWORLDBOOT"
fi

if [[ -n "$ALTOS_HOME" ]]; then
  remove_partition "$ALTOS_HOME"
fi

if [[ -n "$ALTOS_ROOT" ]]; then
  remove_partition "$ALTOS_ROOT"
fi

# --- Remove GRUB from EFI -----------------------------------
log "${BLUE}[INFO] Cleaning up EFI entries...${RESET}"

# Find EFI System Partition
ESP=$(lsblk -rno NAME,PARTTYPE 2>/dev/null | awk '$2=="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print "/dev/" $1}' | head -n1)

if [[ -n "$ESP" ]]; then
  ESP_MOUNT="/tmp/altos_esp_uninstall"
  mkdir -p "$ESP_MOUNT"
  mount "$ESP" "$ESP_MOUNT" 2>/dev/null || true

  # Remove GRUB / rEFInd directories
  if [[ -d "$ESP_MOUNT/EFI/refind" ]]; then
    rm -rf "$ESP_MOUNT/EFI/refind"
    log "${GREEN}[OK] Removed rEFInd from EFI.${RESET}"
  fi

  if [[ -d "$ESP_MOUNT/EFI/grub" ]]; then
    rm -rf "$ESP_MOUNT/EFI/grub"
    log "${GREEN}[OK] Removed GRUB from EFI.${RESET}"
  fi

  umount "$ESP_MOUNT" 2>/dev/null || true
  rmdir "$ESP_MOUNT" 2>/dev/null || true
fi

# Restore Windows Boot Manager priority via efibootmgr
log "${BLUE}[INFO] Restoring Windows Boot Manager...${RESET}"

if command -v efibootmgr &>/dev/null; then
  # Find Windows Boot Manager entry
  WIN_BOOTNUM=$(efibootmgr | grep -i "windows" | head -n1 | sed 's/Boot\([0-9A-Fa-f]*\).*/\1/')
  if [[ -n "$WIN_BOOTNUM" ]]; then
    efibootmgr -o "$WIN_BOOTNUM" 2>/dev/null || true
    log "${GREEN}[OK] Windows Boot Manager set as default boot entry.${RESET}"
  else
    log "${YELLOW}[WARN] Windows Boot Manager entry not found in efibootmgr.${RESET}"
    log "${YELLOW}[WARN] You may need to use your UEFI firmware settings to select Windows.${RESET}"
  fi
else
  log "${YELLOW}[WARN] efibootmgr not available. Cannot auto-restore boot order.${RESET}"
fi

# --- Optionally expand Windows partition --------------------
log ""
read -rp "$(echo -e "${BLUE}[?]${RESET} Expand Windows partition to fill freed space? [y/N]: ")" expand
if [[ "$expand" =~ ^[Yy]$ ]]; then
  WIN_PART=$(lsblk -rno NAME,FSTYPE 2>/dev/null | awk '$2=="ntfs" {print "/dev/" $1}' | head -n1)
  if [[ -n "$WIN_PART" ]]; then
    log "${BLUE}[INFO] Expanding $WIN_PART...${RESET}"
    ntfsresize -f "$WIN_PART" || true
    log "${GREEN}[OK] Windows partition expanded.${RESET}"
  else
    log "${YELLOW}[WARN] No Windows NTFS partition found to expand.${RESET}"
  fi
fi

# --- Finish -------------------------------------------------
log ""
log "${GREEN}=======================================${RESET}"
log "${GREEN}  Uninstall complete${RESET}"
log "${GREEN}=======================================${RESET}"
log "${BLUE}[INFO] Log saved to: $LOG_FILE${RESET}"
log "${BLUE}[INFO] Reboot to boot into Windows.${RESET}"
