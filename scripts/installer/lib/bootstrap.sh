#!/bin/bash
set -euo pipefail

# ============================================================
# bootstrap.sh — Format, mount, and install Fedora base system
# Designed to be sourced by install.sh
# Expects: EFI_PART, ROOT_PART, HOME_PART, DRY_RUN, mode, helpers
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh" 2>/dev/null || true

# Track whether bind mounts were established so cleanup only unmounts what
# this script mounted.
_BIND_MOUNTS_ESTABLISHED=false

_cleanup_bind_mounts() {
  if [[ "$_BIND_MOUNTS_ESTABLISHED" != true ]]; then
    return 0
  fi

  echo ""
  echo -e "${BLUE}[INFO] Unmounting bind mounts...${RESET}"
  for d in proc sys dev etc/resolv.conf; do
    run umount -l "/mnt/$d" || true
  done
  _BIND_MOUNTS_ESTABLISHED=false
  echo -e "${GREEN}[OK] Bind mounts unmounted.${RESET}"
}

bootstrap_system() {
  echo ""
  echo -e "${BLUE}[INFO] Bootstrapping AltOS system...${RESET}"
  echo -e "${BLUE}[INFO] This will download and install Fedora packages. Please wait.${RESET}"

  local install_mode="${mode:-wipe}"

  # --- Format partitions --------------------------------------
  echo ""
  echo -e "${BLUE}[INFO] Formatting partitions...${RESET}"

  run mkfs.btrfs -f "${ROOT_PART}"
  run mkfs.btrfs -f "${HOME_PART}"

  if [[ "$install_mode" == "dualboot" ]]; then
    echo -e "${YELLOW}[WARN] Dual-boot mode: reusing existing EFI partition.${RESET}"
    echo -e "${BLUE}[INFO] Skipping EFI format to preserve Windows bootloader.${RESET}"
  else
    run mkfs.fat -F32 -n ESP "${EFI_PART}"
  fi

  # --- Mount target filesystems -------------------------------
  echo ""
  echo -e "${BLUE}[INFO] Mounting target partitions...${RESET}"

  run mkdir -p /mnt
  if ! mountpoint -q /mnt 2>/dev/null; then
    run mount "${ROOT_PART}" /mnt
  else
    echo -e "${YELLOW}[WARN] /mnt already mounted; skipping root remount.${RESET}"
  fi

  run mkdir -p /mnt/boot/efi /mnt/home /mnt/{proc,sys,dev,etc}

  if ! mountpoint -q /mnt/boot/efi 2>/dev/null; then
    run mount "${EFI_PART}" /mnt/boot/efi
  fi
  if ! mountpoint -q /mnt/home 2>/dev/null; then
    run mount "${HOME_PART}" /mnt/home
  fi

  # --- Bind mount host filesystems into installroot -----------
  echo ""
  echo -e "${BLUE}[INFO] Bind mounting /proc, /sys, /dev, /etc/resolv.conf...${RESET}"

  for d in proc sys dev; do
    if ! mountpoint -q "/mnt/$d" 2>/dev/null; then
      run mount --bind "/$d" "/mnt/$d"
    fi
  done

  if ! mountpoint -q /mnt/etc/resolv.conf 2>/dev/null; then
    run mount --bind /etc/resolv.conf /mnt/etc/resolv.conf
  fi

  _BIND_MOUNTS_ESTABLISHED=true

  # Run the install/configuration phase in a subshell with an EXIT trap so
  # bind mounts are unmounted cleanly even if dnf or fstab generation fails.
  (
    trap '_cleanup_bind_mounts' EXIT

    # --- Install Fedora base system ---------------------------
    echo ""
    echo -e "${BLUE}[INFO] Installing Fedora base system with dnf...${RESET}"

    if [[ "${DRY_RUN}" == true ]]; then
      echo -e "${BLUE}[DRY] Would run: dnf --installroot=/mnt --releasever=42 --nogpgcheck --assumeyes \\
          --disablerepo='*' --enablerepo=fedora --enablerepo=updates install \\
          @core @base-x @kde-desktop kernel kernel-core kernel-modules linux-firmware \\
          grub2-efi-x64 shim-x64 grub2-tools-extra os-prober dnf NetworkManager \\
          pipewire pipewire-pulseaudio wireplumber sddm plasma-desktop \\
          btrfs-progs dosfstools ntfs-3g sbsigntools mokutil efibootmgr${RESET}"
    else
      run dnf --installroot=/mnt --releasever=42 --nogpgcheck --assumeyes \
          --disablerepo='*' --enablerepo=fedora --enablerepo=updates \
          install @core @base-x @kde-desktop \
              kernel kernel-core kernel-modules linux-firmware \
              grub2-efi-x64 shim-x64 grub2-tools-extra \
              os-prober dnf NetworkManager \
              pipewire pipewire-pulseaudio wireplumber \
              sddm plasma-desktop \
              btrfs-progs dosfstools ntfs-3g \
              sbsigntools mokutil efibootmgr
    fi

    # --- Generate /etc/fstab ----------------------------------
    echo ""
    echo -e "${BLUE}[INFO] Generating /etc/fstab...${RESET}"

    if [[ "${DRY_RUN}" == true ]]; then
      echo -e "${BLUE}[DRY] Would write /mnt/etc/fstab with UUIDs.${RESET}"
    else
      local root_uuid home_uuid efi_uuid
      root_uuid=$(blkid -s UUID -o value "${ROOT_PART}")
      home_uuid=$(blkid -s UUID -o value "${HOME_PART}")
      efi_uuid=$(blkid -s UUID -o value "${EFI_PART}")

      cat > /mnt/etc/fstab <<EOF
UUID=${root_uuid} /     btrfs defaults,noatime 0 0
UUID=${home_uuid} /home btrfs defaults,noatime 0 0
UUID=${efi_uuid}  /boot/efi vfat defaults,noatime,umask=0077 0 2
EOF

      echo -e "${GREEN}[OK] /etc/fstab written.${RESET}"
    fi

    # --- Trigger SELinux relabel on first boot ----------------
    echo ""
    echo -e "${BLUE}[INFO] Scheduling SELinux autorelabel on first boot...${RESET}"

    if [[ "${DRY_RUN}" == true ]]; then
      echo -e "${BLUE}[DRY] Would touch /mnt/.autorelabel.${RESET}"
    else
      run touch /mnt/.autorelabel
    fi
  )

  _BIND_MOUNTS_ESTABLISHED=false

  echo -e "${GREEN}[OK] Base system installed.${RESET}"
}
