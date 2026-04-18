#!/bin/bash
set -euo pipefail

# ============================================================
# bootloader.sh — GRUB installation for UEFI + Windows detect
# Designed to be sourced by install.sh
# ============================================================

install_bootloader() {
  echo ""
  echo -e "${BLUE}[INFO] Installing GRUB bootloader for UEFI...${RESET}"

  run arch-chroot /mnt grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=GRUB

  echo ""
  echo -e "${BLUE}[INFO] Enabling os-prober to detect Windows...${RESET}"

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would append to /mnt/etc/default/grub:${RESET}"
    echo -e "${BLUE}[DRY]   GRUB_DISABLE_OS_PROBER=false${RESET}"
  else
    if ! grep -q '^GRUB_DISABLE_OS_PROBER=false' /mnt/etc/default/grub; then
      echo 'GRUB_DISABLE_OS_PROBER=false' >> /mnt/etc/default/grub
      echo -e "${GREEN}[OK] os-prober enabled.${RESET}"
    else
      echo -e "${GREEN}[OK] os-prober already enabled.${RESET}"
    fi
  fi

  echo ""
  echo -e "${BLUE}[INFO] Generating GRUB configuration...${RESET}"
  run arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

  echo -e "${GREEN}[OK] Bootloader installed.${RESET}"
}
