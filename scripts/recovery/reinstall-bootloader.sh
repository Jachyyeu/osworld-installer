#!/bin/bash
set -euo pipefail

# ============================================================
# reinstall-bootloader.sh — Reinstall GRUB + os-prober
# ============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

find_altos_root() {
  lsblk -rno NAME,FSTYPE,LABEL,PARTLABEL 2>/dev/null | awk '$2=="btrfs" && ($4=="Linux Root" || $3=="Linux Root") {print "/dev/" $1}' | head -n1
}

find_efi_partition() {
  lsblk -rno NAME,PARTTYPE 2>/dev/null | awk '$2=="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print "/dev/" $1}' | head -n1
}

ALTOS_ROOT=$(find_altos_root)
EFI_PART=$(find_efi_partition)
MOUNT_POINT="/mnt/rescue"

if [[ -z "$ALTOS_ROOT" ]]; then
  echo -e "${RED}[FAIL] No AltOS root partition found.${RESET}"
  exit 1
fi

if [[ -z "$EFI_PART" ]]; then
  echo -e "${RED}[FAIL] No EFI System Partition found.${RESET}"
  exit 1
fi

echo -e "${BLUE}[INFO] Mounting AltOS root: $ALTOS_ROOT${RESET}"
mkdir -p "$MOUNT_POINT"
mount "$ALTOS_ROOT" "$MOUNT_POINT"

echo -e "${BLUE}[INFO] Mounting EFI: $EFI_PART${RESET}"
mkdir -p "$MOUNT_POINT/boot/efi"
mount "$EFI_PART" "$MOUNT_POINT/boot/efi"

# Bind mount necessary filesystems for chroot
echo -e "${BLUE}[INFO] Preparing chroot environment...${RESET}"
mount --bind /dev "$MOUNT_POINT/dev"
mount --bind /proc "$MOUNT_POINT/proc"
mount --bind /sys "$MOUNT_POINT/sys"

# Reinstall GRUB
echo -e "${BLUE}[INFO] Reinstalling GRUB...${RESET}"
arch-chroot "$MOUNT_POINT" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck || true

# Enable os-prober
echo -e "${BLUE}[INFO] Enabling os-prober...${RESET}"
if grep -q '^GRUB_DISABLE_OS_PROBER=' "$MOUNT_POINT/etc/default/grub"; then
  sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' "$MOUNT_POINT/etc/default/grub"
else
  echo 'GRUB_DISABLE_OS_PROBER=false' >> "$MOUNT_POINT/etc/default/grub"
fi

# Regenerate config
echo -e "${BLUE}[INFO] Regenerating GRUB config...${RESET}"
arch-chroot "$MOUNT_POINT" grub-mkconfig -o /boot/grub/grub.cfg || true

# Update EFI boot entries
echo -e "${BLUE}[INFO] Updating EFI boot entries...${RESET}"
arch-chroot "$MOUNT_POINT" efibootmgr --create --disk /dev/sda --part 1 --loader /EFI/GRUB/grubx64.efi --label "AltOS" || true

# Unmount
echo -e "${BLUE}[INFO] Cleaning up...${RESET}"
umount "$MOUNT_POINT/dev" 2>/dev/null || true
umount "$MOUNT_POINT/proc" 2>/dev/null || true
umount "$MOUNT_POINT/sys" 2>/dev/null || true
umount "$MOUNT_POINT/boot/efi" 2>/dev/null || true
umount "$MOUNT_POINT" 2>/dev/null || true

echo -e "${GREEN}[OK] Bootloader reinstalled successfully.${RESET}"
echo -e "${BLUE}[INFO] Reboot to test.${RESET}"
