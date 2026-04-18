#!/bin/bash
set -euo pipefail

# ============================================================
# disk.sh — Disk partitioning library
# Designed to be sourced by install.sh
# Expects: DRY_RUN, target_disk, mode, and color helpers
# ============================================================

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
  # Return the first (usually largest) NTFS partition name, e.g. sda2
  lsblk -rbno NAME,FSTYPE "$disk" 2>/dev/null | awk '$2=="ntfs" {print $1}' | head -n1
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

  elif [[ "$mode" == "dual_boot" ]]; then
    echo -e "${BLUE}[INFO] Dual-boot mode: making room next to Windows...${RESET}"

    local ntfs_name
    ntfs_name=$(find_ntfs_partition "$disk")

    if [[ -z "$ntfs_name" ]]; then
      echo -e "${RED}[FAIL] No NTFS partition found on ${disk}.${RESET}"
      echo -e "${RED}[FAIL] Cannot set up dual-boot without Windows.${RESET}"
      exit 1
    fi

    local ntfs_path="/dev/${ntfs_name}"
    echo -e "${YELLOW}[WARN] Found Windows partition: ${ntfs_path}${RESET}"
    echo -e "${YELLOW}[WARN] Will shrink by ~22 GiB to create Linux partitions.${RESET}"

    if [[ "$DRY_RUN" == true ]]; then
      echo -e "${BLUE}[DRY] Would run: ntfsresize -f -s <new_size> ${ntfs_path}${RESET}"
      echo -e "${BLUE}[DRY] Would run: parted -s ${disk} resizepart <num> <new_size>${RESET}"
    else
      local current_bytes new_bytes
      current_bytes=$(blockdev --getsize64 "$ntfs_path")
      new_bytes=$((current_bytes - 23622320128)) # 22 GiB

      echo -e "${BLUE}[INFO] Current NTFS size: ${current_bytes} bytes${RESET}"
      echo -e "${BLUE}[INFO] New NTFS size:     ${new_bytes} bytes${RESET}"

      run ntfsresize -f -s "$new_bytes" "$ntfs_path"

      local part_num
      part_num=$(echo "$ntfs_name" | grep -o '[0-9]*$')
      run parted -s "$disk" resizepart "$part_num" "${new_bytes}B"
    fi

    echo -e "${BLUE}[INFO] Creating Linux partitions in freed space...${RESET}"

    run sgdisk -n 0:0:+512M -t 0:ef00 -c 0:"EFI System Partition" "$disk"
    run sgdisk -n 0:0:+20G  -t 0:8304 -c 0:"Linux Root"           "$disk"
    run sgdisk -n 0:0:0     -t 0:8302 -c 0:"Linux Home"           "$disk"

  else
    echo -e "${RED}[FAIL] Unknown installation mode: ${mode}${RESET}"
    echo -e "${RED}[FAIL] Expected 'wipe' or 'dual_boot'.${RESET}"
    exit 1
  fi

  echo -e "${BLUE}[INFO] Notifying kernel of partition changes...${RESET}"
  run partprobe "$disk"
  sleep 2
  echo -e "${GREEN}[OK] Partitioning complete.${RESET}"
}

get_partitions() {
  local disk="$1"

  echo -e "${BLUE}[INFO] Locating Linux partitions on ${disk}...${RESET}"

  partprobe "$disk" &>/dev/null || true

  EFI_PART=$(lsblk -rno NAME,PARTLABEL "$disk" 2>/dev/null | awk '$2=="EFI System Partition" {print "/dev/" $1}')
  ROOT_PART=$(lsblk -rno NAME,PARTLABEL "$disk" 2>/dev/null | awk '$2=="Linux Root" {print "/dev/" $1}')
  HOME_PART=$(lsblk -rno NAME,PARTLABEL "$disk" 2>/dev/null | awk '$2=="Linux Home" {print "/dev/" $1}')

  echo -e "${GREEN}[OK] EFI  partition: ${EFI_PART:-<not found>}${RESET}"
  echo -e "${GREEN}[OK] Root partition: ${ROOT_PART:-<not found>}${RESET}"
  echo -e "${GREEN}[OK] Home partition: ${HOME_PART:-<not found>}${RESET}"
}
