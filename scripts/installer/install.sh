#!/bin/bash
set -euo pipefail

# ============================================================
# install.sh — Main Linux installation script
# Runs inside Arch Live ISO. Reads /tmp/install-config.json.
# Usage:
#   sudo bash install.sh --dry-run   (show plan, touch nothing)
#   sudo bash install.sh --confirm   (execute installation)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# --- Colors -------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# --- DRY_RUN mode -------------------------------------------
DRY_RUN=false

run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would: $*${RESET}"
    return 0
  fi
  echo -e "${GREEN}[OK] Running: $*${RESET}"
  "$@"
}

# --- Safety checks ------------------------------------------
check_mounted() {
  local disk="$1"
  if lsblk -rno MOUNTPOINT "$disk" 2>/dev/null | grep -qE '[^[:space:]]'; then
    echo -e "${RED}[FAIL] ${disk} or one of its partitions is currently mounted.${RESET}"
    echo -e "${RED}[FAIL] This usually means you selected the Live USB itself.${RESET}"
    echo -e "${RED}[FAIL] Aborting to protect your running system.${RESET}"
    exit 1
  fi
}

verify_environment() {
  echo -e "${BLUE}[INFO] Verifying installation environment...${RESET}"

  # Must be root
  if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}[FAIL] This script must be run as root (use sudo).${RESET}"
    exit 1
  fi
  echo -e "${GREEN}[OK] Running as root.${RESET}"

  # UEFI only
  if [[ ! -d /sys/firmware/efi/efivars ]]; then
    echo -e "${RED}[FAIL] UEFI mode not detected.${RESET}"
    echo -e "${RED}[FAIL] This installer only supports UEFI systems.${RESET}"
    exit 1
  fi
  echo -e "${GREEN}[OK] UEFI mode detected.${RESET}"

  # Internet connection
  if ! ping -c 1 -W 5 archlinux.org &>/dev/null; then
    echo -e "${RED}[FAIL] Internet connection not detected.${RESET}"
    echo -e "${RED}[FAIL] Cannot download packages. Check your network.${RESET}"
    exit 1
  fi
  echo -e "${GREEN}[OK] Internet connection detected.${RESET}"
}

# --- Config parsing -----------------------------------------
parse_config() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    echo -e "${RED}[FAIL] Configuration file not found: ${config_file}${RESET}"
    echo -e "${YELLOW}[WARN] The GUI should write this file before starting installation.${RESET}"
    exit 1
  fi

  echo -e "${BLUE}[INFO] Loading installation configuration...${RESET}"

  target_disk=$(python3 -c "import json; print(json.load(open('$config_file')).get('target_disk',''))")
  mode=$(python3 -c "import json; print(json.load(open('$config_file')).get('mode','wipe'))")
  hostname=$(python3 -c "import json; print(json.load(open('$config_file')).get('hostname','archlinux'))")
  username=$(python3 -c "import json; print(json.load(open('$config_file')).get('username','user'))")
  password=$(python3 -c "import json; print(json.load(open('$config_file')).get('password',''))")
  timezone=$(python3 -c "import json; print(json.load(open('$config_file')).get('timezone','UTC'))")
  locale=$(python3 -c "import json; print(json.load(open('$config_file')).get('locale','en_US.UTF-8'))")
  keymap=$(python3 -c "import json; print(json.load(open('$config_file')).get('keymap','us'))")

  echo -e "${GREEN}[OK] Configuration loaded.${RESET}"
  echo -e "${BLUE}       Disk:     ${target_disk}${RESET}"
  echo -e "${BLUE}       Mode:     ${mode}${RESET}"
  echo -e "${BLUE}       Hostname: ${hostname}${RESET}"
  echo -e "${BLUE}       User:     ${username}${RESET}"
}

# --- Main ---------------------------------------------------
main() {
  DRY_RUN=false
  CONFIRM=false

  for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY_RUN=true ;;
      --confirm) CONFIRM=true ;;
    esac
  done

  if [[ "$CONFIRM" == true && "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}[WARN] Both --confirm and --dry-run given. Using --dry-run.${RESET}"
    CONFIRM=false
  fi

  if [[ "$DRY_RUN" == false && "$CONFIRM" == false ]]; then
    echo -e "${YELLOW}[WARN] No action flag specified. Defaulting to --dry-run.${RESET}"
    DRY_RUN=true
  fi

  verify_environment
  parse_config "/tmp/install-config.json"

  if [[ -z "${target_disk:-}" ]]; then
    echo -e "${RED}[FAIL] target_disk is not set in configuration.${RESET}"
    exit 1
  fi

  check_mounted "$target_disk"

  # Source libraries
  source "$LIB_DIR/disk.sh"
  source "$LIB_DIR/bootstrap.sh"
  source "$LIB_DIR/bootloader.sh"
  source "$LIB_DIR/system.sh"

  echo ""
  echo -e "${BLUE}========================================${RESET}"
  echo -e "${BLUE}  INSTALLATION PLAN${RESET}"
  echo -e "${BLUE}========================================${RESET}"
  echo ""

  # Step 1 — Partition
  partition_disk "$target_disk" "$mode"

  # Step 2 — Detect partitions
  get_partitions "$target_disk"

  if [[ -z "${EFI_PART:-}" || -z "${ROOT_PART:-}" || -z "${HOME_PART:-}" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      echo -e "${YELLOW}[WARN] Partitions not found because this is a dry run. Using predicted paths.${RESET}"
      EFI_PART=$(get_partition_name "$target_disk" 1)
      ROOT_PART=$(get_partition_name "$target_disk" 2)
      HOME_PART=$(get_partition_name "$target_disk" 3)
    else
      echo -e "${RED}[FAIL] Could not find all required partitions after partitioning.${RESET}"
      exit 1
    fi
  fi

  # Step 3 — Format & mount
  format_and_mount_partitions

  # Step 4 — Bootstrap base system
  bootstrap_system

  # Step 5 — Bootloader
  install_bootloader

  # Step 6 — System configuration
  configure_system "$hostname" "$username" "$password" "$timezone" "$locale" "$keymap"

  echo ""
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW}  DRY RUN COMPLETE${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW}No changes were made to any disk.${RESET}"
    echo -e "${YELLOW}Run with --confirm to execute for real.${RESET}"
  else
    echo -e "${GREEN}========================================${RESET}"
    echo -e "${GREEN}  INSTALLATION COMPLETE${RESET}"
    echo -e "${GREEN}========================================${RESET}"
    echo -e "${GREEN}You can now reboot into your new system.${RESET}"
  fi
}

main "$@"
