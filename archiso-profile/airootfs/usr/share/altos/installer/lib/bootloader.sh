#!/bin/bash
set -euo pipefail

# ============================================================
# bootloader.sh — GRUB installation for UEFI + Windows detect
# Designed to be sourced by install.sh
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh" 2>/dev/null || true

install_bootloader() {
  echo ""
  echo -e "${BLUE}[INFO] Installing GRUB bootloader for UEFI...${RESET}"

  # Try normal install first (creates NVRAM boot entry on real hardware).
  # Fall back to --removable when EFI variables are unavailable (common in VMs
  # or firmware that does not expose NVRAM to the live environment).
  if arch-chroot /mnt grub-install \
       --target=x86_64-efi \
       --efi-directory=/boot/efi \
       --bootloader-id=GRUB 2>/tmp/grub-install.err; then
    echo -e "${GREEN}[OK] GRUB installed and registered in NVRAM.${RESET}"
  else
    echo -e "${YELLOW}[WARN] Standard GRUB install failed (likely no EFI variables).${RESET}"
    echo -e "${YELLOW}[WARN] Falling back to removable EFI install...${RESET}"
    run arch-chroot /mnt grub-install \
      --target=x86_64-efi \
      --efi-directory=/boot/efi \
      --bootloader-id=GRUB \
      --removable
  fi

  echo ""
  echo -e "${BLUE}[INFO] Enabling os-prober to detect Windows...${RESET}"

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would ensure GRUB_DISABLE_OS_PROBER=false in /mnt/etc/default/grub${RESET}"
  else
    if grep -q '^GRUB_DISABLE_OS_PROBER=' /mnt/etc/default/grub; then
      # Replace any existing value (including true)
      run sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /mnt/etc/default/grub
      echo -e "${GREEN}[OK] os-prober enabled (replaced existing value).${RESET}"
    else
      echo 'GRUB_DISABLE_OS_PROBER=false' >> /mnt/etc/default/grub
      echo -e "${GREEN}[OK] os-prober enabled.${RESET}"
    fi
  fi

  echo ""
  echo -e "${BLUE}[INFO] Configuring serial console for GRUB...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would add console=ttyS0,115200 to GRUB_CMDLINE_LINUX_DEFAULT${RESET}"
  else
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /mnt/etc/default/grub; then
      run sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 console=ttyS0,115200"/' /mnt/etc/default/grub
    else
      echo 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet console=ttyS0,115200"' >> /mnt/etc/default/grub
    fi
    echo -e "${GREEN}[OK] Serial console added to kernel command line.${RESET}"
  fi

  echo ""
  echo -e "${BLUE}[INFO] Generating GRUB configuration...${RESET}"
  run arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

  echo -e "${GREEN}[OK] Bootloader installed.${RESET}"
}
