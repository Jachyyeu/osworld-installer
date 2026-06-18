#!/bin/bash
# ============================================================
# Force-boot into the AltOS installer from an existing Linux install
# Run this on a PC that already has AltOS/OSWORLDBOOT staged but keeps
# booting into another OS (e.g. an existing Arch install).
# ============================================================
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "This script must be run as root. Try: sudo $0"
  exit 1
fi

# Try to find the rEFInd bootloader installed by the AltOS Windows installer.
# It lives on an EFI System Partition (ESP), usually under /boot/efi or /efi.
find_refind_esp() {
  local esp
  for esp in /boot/efi /efi /boot; do
    if [[ -f "${esp}/EFI/refind/refind_x64.efi" ]]; then
      echo "$esp"
      return 0
    fi
    if [[ -f "${esp}/EFI/BOOT/shimx64.efi" ]]; then
      echo "$esp"
      return 0
    fi
  done
  return 1
}

# Find the OSWORLDBOOT partition as a fallback
find_osworldboot() {
  lsblk -o NAME,LABEL,TYPE,PATH -pn | awk '$2 == "OSWORLDBOOT" {print $4}' | head -1
}

# Find the ESP containing rEFInd
ESP="$(find_refind_esp || true)"

if [[ -n "$ESP" ]]; then
  echo "Found AltOS bootloader on: $ESP"

  # Determine the disk and partition number of the ESP
  PART="$(findmnt -n -o SOURCE "$ESP" || true)"
  if [[ -z "$PART" ]]; then
    # Fallback: find the ESP partition by mount point
    PART="$(lsblk -o NAME,MOUNTPOINT,PATH -pn | awk -v esp="$ESP" '$2 == esp {print $3}' | head -1)"
  fi

  if [[ -z "$PART" ]]; then
    echo "ERROR: Could not determine the partition for $ESP"
    exit 1
  fi

  DISK="$(lsblk -no PKNAME "$PART" | head -1)"
  PARTNUM="$(lsblk -no PARTN "$PART" | head -1)"

  if [[ -f "${ESP}/EFI/refind/refind_x64.efi" ]]; then
    LOADER='\EFI\refind\refind_x64.efi'
    LABEL="AltOS Installer (rEFInd)"
  else
    LOADER='\EFI\BOOT\shimx64.efi'
    LABEL="AltOS Installer (Secure Boot)"
  fi
else
  echo "rEFInd not found; trying OSWORLDBOOT partition..."
  PART="$(find_osworldboot)"

  if [[ -z "$PART" ]]; then
    echo "ERROR: Neither rEFInd nor OSWORLDBOOT found."
    echo "You need to run the AltOS Windows installer first to stage the installer."
    exit 1
  fi

  DISK="$(lsblk -no PKNAME "$PART" | head -1)"
  PARTNUM="$(lsblk -no PARTN "$PART" | head -1)"
  LOADER='\EFI\BOOT\BOOTx64.EFI'
  LABEL="AltOS Installer"
fi

DISK_PATH="/dev/$DISK"
echo "Disk: $DISK_PATH, partition: $PARTNUM, loader: $LOADER"

echo "Creating EFI boot entry..."
efibootmgr -c -d "$DISK_PATH" -p "$PARTNUM" -L "$LABEL" -l "$LOADER" >/dev/null

# Get the boot number of the entry we just created
BOOTNUM="$(efibootmgr | grep -i "$LABEL" | head -1 | awk '{print $1}' | tr -d 'Boot*')"

if [[ -z "$BOOTNUM" ]]; then
  echo "ERROR: Could not find the boot entry we just created."
  exit 1
fi

echo "Boot entry created: $BOOTNUM"
echo "Setting it as the one-time next boot..."
efibootmgr -n "$BOOTNUM" >/dev/null

echo ""
echo "Next reboot will boot into the AltOS installer."
read -rp "Reboot now? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  reboot
else
  echo "Run 'reboot' when ready."
fi
