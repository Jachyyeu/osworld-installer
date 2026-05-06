#!/bin/bash
set -euo pipefail

# ============================================================
# disk.sh — Disk partitioning library
# Designed to be sourced by install.sh
# Expects: DRY_RUN, target_disk, mode, and color helpers
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh" 2>/dev/null || true

get_partition_name() {
  local disk="$1"
  local num="$2"
  if [[ "$disk" =~ (nvme|mmcblk) ]]; then
    echo "${disk}p${num}"
  else
    echo "${disk}${num}"
  fi
}

find_ntfs_partition() {
  local disk="$1"
  lsblk -rbno NAME,FSTYPE "$disk" 2>/dev/null | awk '$2=="ntfs" {print $1}' | head -n1
}

# Find existing EFI partition(s) on a disk
find_efi_partitions() {
  local disk="$1"
  lsblk -rno NAME,PARTTYPE "$disk" 2>/dev/null | awk '$2=="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print "/dev/" $1}'
}

# Count EFI partitions on a disk
count_efi_partitions() {
  local disk="$1"
  find_efi_partitions "$disk" | wc -l
}

partition_disk() {
  local disk="$1"
  local mode="$2"

  echo -e "${BLUE}[INFO] Preparing disk: ${disk}${RESET}"
  echo -e "${BLUE}[INFO] Mode: ${mode}${RESET}"

  if [[ "$mode" == "wipe" ]]; then
    echo -e "${YELLOW}[WARN] ========================================${RESET}"
    echo -e "${YELLOW}[WARN]  WIPE MODE SELECTED${RESET}"
    echo -e "${YELLOW}[WARN]  ALL DATA ON ${disk} WILL BE DESTROYED${RESET}"
    echo -e "${YELLOW}[WARN] ========================================${RESET}"

    run sgdisk -Z "$disk"
    run sgdisk -o "$disk"

    echo -e "${BLUE}[INFO] Creating new GPT partition table...${RESET}"

    run sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System Partition" "$disk"
    run sgdisk -n 2:0:+20G  -t 2:8304 -c 2:"Linux Root"           "$disk"
    run sgdisk -n 3:0:0     -t 3:8302 -c 3:"Linux Home"           "$disk"

  elif [[ "$mode" == "dualboot" ]]; then
    echo -e "${BLUE}[INFO] Dual-boot mode: reusing existing Windows EFI...${RESET}"

    local ntfs_name
    ntfs_name=$(find_ntfs_partition "$disk")

    if [[ -z "$ntfs_name" ]]; then
      echo -e "${RED}[FAIL] No NTFS partition found on ${disk}.${RESET}"
      echo -e "${RED}[FAIL] Cannot set up dual-boot without Windows.${RESET}"
      exit 1
    fi

    # Safety check: count existing EFI partitions
    local efi_count
    efi_count=$(count_efi_partitions "$disk")
    if [[ "$efi_count" -gt 1 ]]; then
      echo -e "${RED}[FAIL] Multiple EFI partitions detected on ${disk} (${efi_count}).${RESET}"
      echo -e "${RED}[FAIL] Aborting to prevent accidental data loss.${RESET}"
      echo -e "${YELLOW}[WARN] Please manually verify your disk layout before retrying.${RESET}"
      exit 1
    fi
    if [[ "$efi_count" -eq 0 ]]; then
      echo -e "${RED}[FAIL] No existing EFI partition found on ${disk}.${RESET}"
      echo -e "${RED}[FAIL] Windows EFI system partition is required for dual-boot.${RESET}"
      exit 1
    fi

    local ntfs_path="/dev/${ntfs_name}"
    echo -e "${YELLOW}[WARN] Found Windows partition: ${ntfs_path}${RESET}"
    echo -e "${YELLOW}[WARN] Will shrink by ~20 GiB to create Linux partitions.${RESET}"

    if [[ "$DRY_RUN" == true ]]; then
      echo -e "${BLUE}[DRY] Would run: ntfsresize -f -s <new_size> ${ntfs_path}${RESET}"
      echo -e "${BLUE}[DRY] Would run: parted -s ${disk} resizepart <num> <new_size>${RESET}"
    else
      local current_bytes new_bytes
      current_bytes=$(blockdev --getsize64 "$ntfs_path")
      new_bytes=$((current_bytes - 21474836480)) # 20 GiB

      echo -e "${BLUE}[INFO] Current NTFS size: ${current_bytes} bytes${RESET}"
      echo -e "${BLUE}[INFO] New NTFS size:     ${new_bytes} bytes${RESET}"

      run ntfsresize -f -s "$new_bytes" "$ntfs_path"

      local part_num
      part_num=$(echo "$ntfs_name" | grep -o '[0-9]*$')
      run parted -s "$disk" resizepart "$part_num" "${new_bytes}B"
    fi

    echo -e "${BLUE}[INFO] Creating Linux partitions in freed space...${RESET}"

    # In dualboot: ONLY root and home. NO second EFI.
    run sgdisk -n 0:0:+20G  -t 0:8304 -c 0:"Linux Root" "$disk"
    run sgdisk -n 0:0:0     -t 0:8302 -c 0:"Linux Home" "$disk"

  else
    echo -e "${RED}[FAIL] Unknown installation mode: ${mode}${RESET}"
    echo -e "${RED}[FAIL] Expected 'wipe' or 'dualboot'.${RESET}"
    exit 1
  fi

  echo -e "${BLUE}[INFO] Notifying kernel of partition changes...${RESET}"
  run partprobe "$disk"
  sleep 2
  echo -e "${GREEN}[OK] Partitioning complete.${RESET}"
}

get_partitions() {
  local disk="$1"
  local mode="${2:-wipe}"

  echo -e "${BLUE}[INFO] Locating partitions on ${disk}...${RESET}"

  partprobe "$disk" &>/dev/null || true

  if [[ "$mode" == "dualboot" ]]; then
    # In dualboot: find the EXISTING Windows EFI partition
    EFI_PART=$(find_efi_partitions "$disk" | head -n1)
    if [[ -z "$EFI_PART" ]]; then
      echo -e "${RED}[FAIL] Could not find existing EFI partition on ${disk}.${RESET}"
      exit 1
    fi
  else
    # In wipe mode: find the NEW EFI partition we just created
    EFI_PART=$(lsblk -rno NAME,PARTLABEL "$disk" 2>/dev/null | awk '$2=="EFI System Partition" {print "/dev/" $1}' || true)
  fi

  ROOT_PART=$(lsblk -rno NAME,PARTLABEL "$disk" 2>/dev/null | awk '$2=="Linux Root" {print "/dev/" $1}' || true)
  HOME_PART=$(lsblk -rno NAME,PARTLABEL "$disk" 2>/dev/null | awk '$2=="Linux Home" {print "/dev/" $1}' || true)

  echo -e "${GREEN}[OK] EFI  partition: ${EFI_PART:-<not found>}${RESET}"
  echo -e "${GREEN}[OK] Root partition: ${ROOT_PART:-<not found>}${RESET}"
  echo -e "${GREEN}[OK] Home partition: ${HOME_PART:-<not found>}${RESET}"
}

format_and_mount_partitions() {
  local mode="${1:-wipe}"

  echo ""
  echo -e "${BLUE}[INFO] Formatting partitions...${RESET}"

  if [[ "$mode" == "dualboot" ]]; then
    # CRITICAL: DO NOT format the existing Windows EFI partition in dualboot mode
    echo -e "${YELLOW}[WARN] Dual-boot mode: skipping EFI format (reusing Windows ESP).${RESET}"
    echo -e "${BLUE}[INFO] Will mount existing EFI partition ${EFI_PART} without formatting.${RESET}"
  else
    run mkfs.fat -F32 "$EFI_PART"
  fi

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
