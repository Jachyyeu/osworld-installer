#!/bin/bash
set -euo pipefail

# ============================================================
# bootstrap.sh — Format, mount, and install base system
# Designed to be sourced by install.sh
# Expects: EFI_PART, ROOT_PART, HOME_PART, DRY_RUN, helpers
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh" 2>/dev/null || true

# --- YAML helpers -------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$SCRIPT_DIR")"
ALTOS_DIR="$(dirname "$INSTALLER_DIR")"
PACKAGES_YAML="${ALTOS_DIR}/packages/basic.yaml"

# Extract a simple indented list from YAML (e.g. base_packages or services.enabled)
# Usage: extract_yaml_list <file> <section_key> <indent_level>
extract_yaml_list() {
  local file="$1"
  local section="$2"
  local indent="$3"
  awk -v section="^${section}:" -v indent="^${indent}- " '
    $0 ~ section { in_section=1; next }
    in_section && /^[a-zA-Z_]/ { exit }
    in_section && $0 ~ indent { sub(/^[^-]+- /, ""); print }
  ' "$file"
}

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
  echo -e "${BLUE}[INFO] Bootstrapping AltOS system...${RESET}"
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

  # Merge packages from packages/basic.yaml if available
  if [[ -f "$PACKAGES_YAML" ]]; then
    echo -e "${BLUE}[INFO] Reading additional packages from ${PACKAGES_YAML}...${RESET}"
    local yaml_pkgs
    yaml_pkgs=$(extract_yaml_list "$PACKAGES_YAML" "base_packages" "  ")
    if [[ -n "$yaml_pkgs" ]]; then
      while IFS= read -r pkg; do
        # Skip duplicates
        local found=0
        for existing in "${packages[@]}"; do
          if [[ "$existing" == "$pkg" ]]; then
            found=1
            break
          fi
        done
        if [[ "$found" -eq 0 ]]; then
          packages+=("$pkg")
        fi
      done <<< "$yaml_pkgs"
      echo -e "${GREEN}[OK] Added packages from basic.yaml.${RESET}"
    fi
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would run: pacstrap /mnt ${packages[*]}${RESET}"
  else
    # Pipe yes so pacman does not block on provider/confirmation prompts when
    # stdin is not a TTY (e.g. running under systemd in the live environment).
    # Temporarily disable pipefail because `yes` exits with SIGPIPE (141) when
    # pacstrap closes the pipe after finishing successfully.
    set +o pipefail
    yes | run pacstrap /mnt "${packages[@]}"
    local pacstrap_rc=$?
    set -o pipefail
    if [[ $pacstrap_rc -ne 0 && $pacstrap_rc -ne 141 ]]; then
      echo -e "${RED}[FAIL] pacstrap failed with exit code ${pacstrap_rc}.${RESET}"
      exit $pacstrap_rc
    fi
  fi

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
