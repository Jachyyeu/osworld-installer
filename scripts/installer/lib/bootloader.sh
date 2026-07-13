#!/bin/bash
set -euo pipefail

# ============================================================
# bootloader.sh — Fedora GRUB2 installation for UEFI + Windows detect
# Designed to be sourced by install.sh
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh" 2>/dev/null || true

install_bootloader() {
  echo ""
  echo -e "${BLUE}[INFO] Installing Fedora GRUB2 bootloader for UEFI...${RESET}"

  local install_mode="${mode:-wipe}"
  local grub_args=(
    --target=x86_64-efi
    --efi-directory=/boot/efi
    --bootloader-id=fedora
  )

  # In dual-boot mode, never use --removable: it would overwrite the
  # Windows fallback bootloader at \EFI\Boot\bootx64.efi.  The standard
  # install creates a dedicated \EFI\fedora entry and updates NVRAM.
  if [[ "$install_mode" != "dualboot" ]]; then
    # Wipe mode: if normal install fails (e.g. no EFI variables in a VM),
    # fall back to --removable because there is no Windows to protect.
    if chroot /mnt grub2-install "${grub_args[@]}" 2>/tmp/grub-install.err; then
      echo -e "${GREEN}[OK] GRUB2 installed and registered in NVRAM.${RESET}"
    else
      echo -e "${YELLOW}[WARN] Standard GRUB2 install failed (likely no EFI variables).${RESET}"
      echo -e "${YELLOW}[WARN] Falling back to removable EFI install...${RESET}"
      run chroot /mnt grub2-install --removable "${grub_args[@]}"
    fi
  else
    echo -e "${BLUE}[INFO] Dual-boot mode: installing GRUB2 without --removable to protect Windows fallback bootloader.${RESET}"
    run chroot /mnt grub2-install "${grub_args[@]}"
    echo -e "${GREEN}[OK] GRUB2 installed into \\EFI\\fedora.${RESET}"
  fi

  echo ""
  echo -e "${BLUE}[INFO] Enabling os-prober to detect Windows...${RESET}"

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would ensure GRUB_DISABLE_OS_PROBER=false in /mnt/etc/default/grub${RESET}"
  else
    if grep -q '^GRUB_DISABLE_OS_PROBER=' /mnt/etc/default/grub; then
      run sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /mnt/etc/default/grub
      echo -e "${GREEN}[OK] os-prober enabled (replaced existing value).${RESET}"
    else
      echo 'GRUB_DISABLE_OS_PROBER=false' >> /mnt/etc/default/grub
      echo -e "${GREEN}[OK] os-prober enabled.${RESET}"
    fi
  fi

  echo ""
  echo -e "${BLUE}[INFO] Generating GRUB2 configuration...${RESET}"
  run chroot /mnt grub2-mkconfig -o /boot/grub2/grub.cfg

  echo -e "${GREEN}[OK] Bootloader installed.${RESET}"
}
