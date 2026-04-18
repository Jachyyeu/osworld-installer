#!/bin/bash
set -euo pipefail

# ============================================================
# system.sh — System configuration inside chroot
# Designed to be sourced by install.sh
# ============================================================

configure_system() {
  local hostname="$1"
  local username="$2"
  local password="$3"
  local timezone="$4"
  local locale="$5"
  local keymap="$6"

  echo ""
  echo -e "${BLUE}[INFO] Configuring system settings...${RESET}"

  # Timezone
  echo -e "${BLUE}[INFO] Setting timezone to ${timezone}...${RESET}"
  run ln -sf "/usr/share/zoneinfo/${timezone}" /mnt/etc/localtime
  run arch-chroot /mnt hwclock --systohc

  # Locale
  echo -e "${BLUE}[INFO] Configuring locale: ${locale}...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would uncomment ${locale} in /mnt/etc/locale.gen${RESET}"
    echo -e "${BLUE}[DRY] Would run: locale-gen${RESET}"
    echo -e "${BLUE}[DRY] Would create /mnt/etc/locale.conf with LANG=${locale}${RESET}"
  else
    if grep -q "^#${locale}" /mnt/etc/locale.gen; then
      sed -i "s/^#${locale}/${locale}/" /mnt/etc/locale.gen
      echo -e "${GREEN}[OK] Uncommented ${locale} in locale.gen.${RESET}"
    fi
    arch-chroot /mnt locale-gen
    echo "LANG=${locale}" > /mnt/etc/locale.conf
    echo -e "${GREEN}[OK] Locale configured.${RESET}"
  fi

  # Console keymap
  echo -e "${BLUE}[INFO] Setting console keymap to ${keymap}...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would write KEYMAP=${keymap} to /mnt/etc/vconsole.conf${RESET}"
  else
    echo "KEYMAP=${keymap}" > /mnt/etc/vconsole.conf
    echo -e "${GREEN}[OK] Keymap configured.${RESET}"
  fi

  # Hostname
  echo -e "${BLUE}[INFO] Setting hostname to ${hostname}...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would write ${hostname} to /mnt/etc/hostname${RESET}"
    echo -e "${BLUE}[DRY] Would write hosts entries to /mnt/etc/hosts${RESET}"
  else
    echo "$hostname" > /mnt/etc/hostname

    cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   ${hostname}
::1         localhost
EOF
    echo -e "${GREEN}[OK] Hostname and hosts file configured.${RESET}"
  fi

  # User creation
  echo -e "${BLUE}[INFO] Creating user account: ${username}...${RESET}"
  run arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$username"

  echo -e "${BLUE}[INFO] Setting password for ${username}...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would set password for user ${username}${RESET}"
  else
    echo "${username}:${password}" | arch-chroot /mnt chpasswd
    echo -e "${GREEN}[OK] Password set.${RESET}"
  fi

  # Sudo
  echo -e "${BLUE}[INFO] Enabling sudo for the 'wheel' group...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would uncomment '%wheel ALL=(ALL:ALL) ALL' in /mnt/etc/sudoers${RESET}"
  else
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers
    echo -e "${GREEN}[OK] Sudo enabled for wheel group.${RESET}"
  fi

  # NetworkManager
  echo -e "${BLUE}[INFO] Enabling NetworkManager to start on boot...${RESET}"
  run arch-chroot /mnt systemctl enable NetworkManager.service

  echo -e "${GREEN}[OK] System configuration complete.${RESET}"
}
