#!/bin/bash
set -euo pipefail

# ============================================================
# bootstrap.sh — Format, mount, and install base system
# Designed to be sourced by install.sh
# Expects: EFI_PART, ROOT_PART, HOME_PART, DRY_RUN, helpers
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh" 2>/dev/null || true

format_and_mount_partitions() {
  echo ""
  echo -e "${BLUE}[INFO] Formatting partitions...${RESET}"

  run mkfs.fat -F32 "$EFI_PART"
  run mkfs.btrfs -f "$ROOT_PART"
  run mkfs.btrfs -f "$HOME_PART"

  echo ""
  echo -e "${BLUE}[INFO] Mounting partitions...${RESET}"

  run mount "$ROOT_PART" /mnt

  run mkdir -p /mnt/boot/efi
  run mount "$EFI_PART" /mnt/boot/efi

  run mkdir -p /mnt/home
  run mount "$HOME_PART" /mnt/home

  echo -e "${GREEN}[OK] All partitions mounted under /mnt.${RESET}"
}

bootstrap_system() {
  echo ""
  echo -e "${BLUE}[INFO] Bootstrapping Arch Linux base system...${RESET}"
  echo -e "${BLUE}[INFO] This will download and install packages. Please wait.${RESET}"

  local packages=(
    base
    base-devel
    linux
    linux-firmware
    btrfs-progs
    grub
    efibootmgr
    os-prober
    networkmanager
    sudo
    nano
    vim
    intel-ucode
    amd-ucode
  )

  run pacstrap /mnt "${packages[@]}"

  echo ""
  echo -e "${BLUE}[INFO] Generating /etc/fstab...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would run: genfstab -U /mnt >> /mnt/etc/fstab${RESET}"
  else
    run genfstab -U /mnt >> /mnt/etc/fstab
    echo -e "${GREEN}[OK] fstab generated.${RESET}"
  fi

  echo -e "${GREEN}[OK] Base system installed.${RESET}"
}
