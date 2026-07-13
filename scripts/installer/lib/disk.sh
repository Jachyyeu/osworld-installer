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

# Return the amount of free space (in bytes) on an NTFS partition, using
# ntfsresize --info.  This works even when the filesystem is dirty or
# hibernated, as long as the volume metadata is readable.
ntfs_free_bytes() {
  local part="$1"
  local info used_mb vol_bytes used_bytes
  info=$(ntfsresize --info --force --no-progress-bar "$part" 2>/dev/null || true)
  used_mb=$(echo "$info" | grep -i 'Space in use' | grep -oE '[0-9]+' | head -n1)
  vol_bytes=$(echo "$info" | grep -i 'Current volume size' | grep -oE '[0-9]+' | head -n1)
  if [[ -n "$used_mb" && "$used_mb" =~ ^[0-9]+$ && -n "$vol_bytes" && "$vol_bytes" =~ ^[0-9]+$ ]]; then
    used_bytes=$((used_mb * 1000 * 1000))
    echo $((vol_bytes - used_bytes))
  fi
}

find_ntfs_partition() {
  local disk="$1"
  # For dual-boot, shrink the partition with the most usable free space (e.g. D:)
  # rather than the largest total NTFS partition.  This avoids trying to shrink a
  # nearly-full C: drive and protects the Windows system partition.
  local result=""
  result=$(for part in "${disk}"[0-9]* "${disk}"p[0-9]*; do
      [[ -e "$part" ]] || continue
      blkid -s TYPE "$part" 2>/dev/null | grep -qi 'TYPE="ntfs"' || ntfsinfo -m "$part" >/dev/null 2>&1 || continue
      free=$(ntfs_free_bytes "$part")
      [[ -n "$free" && "$free" =~ ^[0-9]+$ ]] || continue
      echo "$(basename "$part") $free"
    done | sort -k2 -n -r | head -n1 | awk '{print $1}') || true
  echo "$result"
}

# Find the NTFS partition with the most free space on *any* disk. Useful when
# Windows is on a different physical disk than the OSWORLDBOOT staging partition.
find_ntfs_partition_any_disk() {
  local result=""
  result=$(lsblk -rno NAME 2>/dev/null \
    | while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        local part="/dev/$name"
        [[ -e "$part" ]] || continue
        blkid -s TYPE "$part" 2>/dev/null | grep -qi 'TYPE="ntfs"' || ntfsinfo -m "$part" >/dev/null 2>&1 || continue
        free=$(ntfs_free_bytes "$part")
        [[ -n "$free" && "$free" =~ ^[0-9]+$ ]] || continue
        echo "$name $free"
      done | sort -k2 -n -r | head -n1 | awk '{print $1}') || true
  echo "$result"
}

# Return the block device (/dev/sda, /dev/nvme0n1, ...) that owns a partition
get_disk_for_partition() {
  local part="$1"
  # Strip /dev/ if present
  part="${part#/dev/}"
  # For nvme/mmcblk, strip trailing pN; for sda/sdb style, strip trailing digits
  if [[ "$part" =~ ^(nvme|mmcblk) ]]; then
    echo "/dev/$(echo "$part" | sed -E 's/p[0-9]+$//')"
  else
    echo "/dev/$(echo "$part" | sed -E 's/[0-9]+$//')"
  fi
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

# Find any EFI partition on the system (for cross-disk dual-boot)
find_any_efi_partition() {
  local result=""
  result=$(lsblk -rno NAME,PARTTYPE 2>/dev/null \
    | awk '$2=="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print "/dev/" $1}' \
    | head -n1) || true
  echo "$result"
}

# Find EFI partition on a specific disk, or fall back to any EFI on the system.
find_efi_partition_for_disk() {
  local disk="$1"
  local efi
  efi=$(find_efi_partitions "$disk" | head -n1 || true)
  if [[ -n "$efi" ]]; then
    echo "$efi"
  else
    find_any_efi_partition
  fi
}

# Returns true (0) if the given partition is the temporary OSWORLDBOOT ESP.
is_osworldboot_partition() {
  local part="$1"
  local partlabel fslabel
  partlabel=$(lsblk -rno PARTLABEL "$part" 2>/dev/null | head -n1 || true)
  fslabel=$(lsblk -rno LABEL "$part" 2>/dev/null | head -n1 || true)
  [[ "$partlabel" == "OSWORLDBOOT" || "$fslabel" == "OSWORLDBOOT" ]]
}

# Find a Windows/system EFI partition for dual-boot, excluding the OSWORLDBOOT
# installer staging partition.  Returns the first match or empty string.
find_windows_efi_for_disk() {
  local disk="$1"
  local efi

  for efi in $(find_efi_partitions "$disk" 2>/dev/null); do
    [[ -n "$efi" ]] || continue
    if is_osworldboot_partition "$efi"; then
      continue
    fi
    echo "$efi"
    return 0
  done

  # Cross-disk fallback, also excluding OSWORLDBOOT
  for efi in $(find_any_efi_partition 2>/dev/null); do
    [[ -n "$efi" ]] || continue
    if is_osworldboot_partition "$efi"; then
      continue
    fi
    echo "$efi"
    return 0
  done

  echo ""
  return 0
}

# Return the amount of unallocated bytes on a disk.
get_unallocated_bytes() {
  local disk="$1"
  local sectors bytes

  # Try sgdisk first (arch live ISO usually has gptfdisk).
  sectors=$(sgdisk -p "$disk" 2>/dev/null | grep -i 'Total free space' | grep -oE '[0-9]+ sectors' | awk '{print $1}')
  if [[ -n "$sectors" && "$sectors" =~ ^[0-9]+$ ]]; then
    echo $((sectors * 512))
    return
  fi

  # Fallback: parted print free.
  bytes=$(parted -s "$disk" unit B print free 2>/dev/null | awk '/Free Space/ {gsub("B",""); print $3}' | tail -n1)
  if [[ -n "$bytes" && "$bytes" =~ ^[0-9]+$ ]]; then
    echo "$bytes"
    return
  fi

  # Fallback: blockdev size minus sum of partition sizes.
  local disk_size part_sum
  disk_size=$(blockdev --getsize64 "$disk")
  part_sum=$(lsblk -rbno SIZE "$disk" 2>/dev/null | tail -n +2 | awk '{s+=$1} END {print s}')
  if [[ -n "$part_sum" && "$part_sum" =~ ^[0-9]+$ ]]; then
    echo $((disk_size - part_sum))
    return
  fi

  echo 0
}

# Check whether an NTFS partition has enough free space to shrink by the
# requested amount.  Returns 0 if yes, 1 if no.
ntfs_can_shrink() {
  local part="$1"
  local shrink_bytes="$2"
  local used_bytes used_mb info

  # ntfsresize --info reports "Space in use : <MB> MB (<percent>%)".
  # Extract the megabyte value and convert to bytes.  ntfsresize uses decimal
  # MB (1 MB = 1 000 000 bytes), so we match that unit here.
  info=$(ntfsresize --info --force --no-progress-bar "$part" 2>/dev/null || true)
  used_mb=$(echo "$info" | grep -i 'Space in use' | grep -oE '[0-9]+' | head -n1)
  if [[ -z "$used_mb" || ! "$used_mb" =~ ^[0-9]+$ ]]; then
    # Can't determine; be pessimistic and require 30% free.
    local total_bytes
    total_bytes=$(blockdev --getsize64 "$part")
    local min_free=$((total_bytes / 10 * 3))
    [[ "$((total_bytes - shrink_bytes))" -ge "$min_free" ]]
    return
  fi
  used_bytes=$((used_mb * 1000 * 1000))
  local current_bytes new_size
  current_bytes=$(blockdev --getsize64 "$part")
  new_size=$((current_bytes - shrink_bytes))
  [[ "$new_size" -gt "$used_bytes" ]]
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
    ntfs_name=$(find_ntfs_partition "$disk" || true)

    local win_disk="$disk"
    if [[ -z "$ntfs_name" ]]; then
      echo -e "${YELLOW}[WARN] No NTFS partition on ${disk}. Searching other disks...${RESET}"
      ntfs_name=$(find_ntfs_partition_any_disk || true)
      if [[ -z "$ntfs_name" ]]; then
        echo -e "${RED}[FAIL] No NTFS partition found on any disk.${RESET}"
        echo -e "${RED}[FAIL] Cannot set up dual-boot without Windows.${RESET}"
        exit 1
      fi
      win_disk=$(get_disk_for_partition "/dev/${ntfs_name}")
      echo -e "${YELLOW}[WARN] Windows partition ${ntfs_name} is on ${win_disk}, not ${disk}.${RESET}"
      echo -e "${YELLOW}[WARN] Linux will still be installed on ${disk}; Windows files will be mounted from ${win_disk}.${RESET}"
    fi

    # Safety check: distinguish the Windows ESP from the OSWORLDBOOT installer ESP.
    # OSWORLDBOOT is intentionally created as an EFI partition so the UEFI Shell
    # can boot the Linux kernel; it is NOT a Windows/AltOS system ESP and must not
    # be counted as a "multiple EFI" conflict.
    local all_efi
    all_efi=$(find_efi_partitions "$win_disk" || true)

    local win_efi_count=0
    local efi
    while IFS= read -r efi; do
      [[ -n "$efi" ]] || continue
      if is_osworldboot_partition "$efi"; then
        echo -e "${BLUE}[INFO] Ignoring OSWORLDBOOT installer ESP ${efi}.${RESET}"
        continue
      fi
      win_efi_count=$((win_efi_count + 1))
    done <<< "$all_efi"

    local cross_disk_efi=""
    if [[ "$win_efi_count" -gt 1 ]]; then
      echo -e "${RED}[FAIL] Multiple Windows/system EFI partitions detected on ${win_disk} (${win_efi_count}).${RESET}"
      echo -e "${RED}[FAIL] Aborting to prevent accidental data loss.${RESET}"
      echo -e "${YELLOW}[WARN] Please manually verify your disk layout before retrying.${RESET}"
      exit 1
    fi
    if [[ "$win_efi_count" -eq 0 ]]; then
      echo -e "${YELLOW}[WARN] No Windows/system EFI on ${win_disk}; searching other disks...${RESET}"
      cross_disk_efi=$(find_any_efi_partition || true)
      if [[ -z "$cross_disk_efi" ]]; then
        echo -e "${RED}[FAIL] No existing EFI partition found on ${win_disk} or any other disk.${RESET}"
        echo -e "${RED}[FAIL] Windows EFI system partition is required for dual-boot.${RESET}"
        exit 1
      fi
      if is_osworldboot_partition "$cross_disk_efi"; then
        echo -e "${RED}[FAIL] Only EFI partition found is the OSWORLDBOOT installer partition.${RESET}"
        echo -e "${RED}[FAIL] Windows EFI system partition is required for dual-boot.${RESET}"
        exit 1
      fi
      echo -e "${YELLOW}[WARN] No EFI partition on ${win_disk}; using cross-disk EFI ${cross_disk_efi}.${RESET}"
    fi

    local ntfs_path="/dev/${ntfs_name}"
    echo -e "${YELLOW}[WARN] Found Windows partition: ${ntfs_path}${RESET}"

    # IMPORTANT: do NOT try to shrink a partition that is not on $disk.
    # The user may have Windows on one disk and want Linux on another.
    local min_required_bytes=$((13 * 1024 * 1024 * 1024)) # 13 GiB headroom
    local unallocated_bytes
    unallocated_bytes=$(get_unallocated_bytes "$disk")
    echo -e "${BLUE}[INFO] Unallocated space on ${disk}: ${unallocated_bytes} bytes${RESET}"

    if [[ "$win_disk" != "$disk" ]]; then
      echo -e "${BLUE}[INFO] Windows partition is on ${win_disk}, not ${disk}. Skipping NTFS resize.${RESET}"
      echo -e "${BLUE}[INFO] Linux partitions will be created in free space on ${disk}.${RESET}"
    elif [[ "$unallocated_bytes" -ge "$min_required_bytes" ]]; then
      echo -e "${BLUE}[INFO] Enough unallocated space on ${disk}; will create Linux partitions without shrinking Windows.${RESET}"
    elif [[ "$DRY_RUN" == true ]]; then
      echo -e "${BLUE}[DRY] Would run: ntfsresize -f -s <new_size> ${ntfs_path}${RESET}"
      echo -e "${BLUE}[DRY] Would run: parted -s ${disk} resizepart <num> <new_end>${RESET}"
    else
      echo -e "${YELLOW}[WARN] Will shrink ${ntfs_path} by ~13 GiB to create Linux partitions.${RESET}"
      local current_bytes new_bytes
      current_bytes=$(blockdev --getsize64 "$ntfs_path")
      new_bytes=$((current_bytes - 13958643712)) # 13 GiB

      echo -e "${BLUE}[INFO] Current NTFS size: ${current_bytes} bytes${RESET}"
      echo -e "${BLUE}[INFO] New NTFS size:     ${new_bytes} bytes${RESET}"

      if [[ "$current_bytes" -lt "$min_required_bytes" ]]; then
        echo -e "${RED}[FAIL] NTFS partition ${ntfs_path} is only ${current_bytes} bytes.${RESET}"
        echo -e "${RED}[FAIL] Need at least ${min_required_bytes} bytes (13 GiB) of free or unallocated space.${RESET}"
        echo -e "${RED}[FAIL] Aborting to protect your Windows data.${RESET}"
        exit 1
      fi

      if ! ntfs_can_shrink "$ntfs_path" 13958643712; then
        echo -e "${RED}[FAIL] NTFS partition ${ntfs_path} does not have enough free space to shrink by 13 GiB.${RESET}"
        echo -e "${RED}[FAIL] Aborting to protect your Windows data.${RESET}"
        exit 1
      fi

      if mountpoint -q "$ntfs_path" 2>/dev/null; then
        echo -e "${RED}[FAIL] NTFS partition ${ntfs_path} is currently mounted.${RESET}"
        echo -e "${RED}[FAIL] Aborting to protect your Windows data.${RESET}"
        exit 1
      fi

      # Ensure the NTFS filesystem is clean before resizing.
      run ntfsfix -b -d "$ntfs_path" || true
      run ntfsresize -f -s "$new_bytes" "$ntfs_path"

      local part_num
      part_num=$(echo "$ntfs_name" | grep -o '[0-9]*$')

      # parted resizepart expects the new END position, not the new size.
      # Compute it as: partition_start + new_bytes.
      local part_start new_end
      part_start=$(parted -s "$disk" unit B print | awk -v num="$part_num" '$1==num {gsub("B",""); print $2}')
      if [[ -z "$part_start" || ! "$part_start" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[FAIL] Could not determine start offset of partition ${part_num} on ${disk}.${RESET}"
        exit 1
      fi
      new_end=$((part_start + new_bytes))

      if [[ "$new_end" -le "$part_start" ]]; then
        echo -e "${RED}[FAIL] Computed new partition end (${new_end}) is not larger than start (${part_start}).${RESET}"
        echo -e "${RED}[FAIL] Aborting to avoid corrupting the partition table.${RESET}"
        exit 1
      fi

      # Ensure the new end does not exceed the current partition end; if it
      # does, something went wrong in the size calculation.
      local current_end
      current_end=$(parted -s "$disk" unit B print | awk -v num="$part_num" '$1==num {gsub("B",""); print $3}')
      if [[ -n "$current_end" && "$current_end" =~ ^[0-9]+$ && "$new_end" -gt "$current_end" ]]; then
        echo -e "${RED}[FAIL] Computed new partition end (${new_end}) is larger than the current end (${current_end}).${RESET}"
        echo -e "${RED}[FAIL] Aborting to avoid corrupting the partition table.${RESET}"
        exit 1
      fi

      # parted resizepart may prompt for confirmation even in script mode;
      # pipe "yes" through pretend-input-tty to accept it automatically.
      run bash -c "yes | parted ---pretend-input-tty '$disk' resizepart '$part_num' '${new_end}B'"
    fi

    echo -e "${BLUE}[INFO] Creating Linux partitions in freed space...${RESET}"

    # In dualboot: ONLY root and home. NO second EFI.
    run sgdisk -n 0:0:+13G  -t 0:8304 -c 0:"Linux Root" "$disk"
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

  # Predictable partition numbers for wipe mode.
  local pred_efi pred_root pred_home
  pred_efi=$(get_partition_name "$disk" 1)
  pred_root=$(get_partition_name "$disk" 2)
  pred_home=$(get_partition_name "$disk" 3)

  # Retry to allow the kernel/udev to create device nodes and labels.
  local attempt=0
  local max_attempts=30
  while [[ $attempt -lt $max_attempts ]]; do
    # Force a rescan using multiple methods; some kernels/VMs need partx/blockdev.
    partprobe "$disk" &>/dev/null || true
    blockdev --rereadpt "$disk" &>/dev/null || true
    command -v partx &>/dev/null && partx -u "$disk" &>/dev/null || true

    if [[ "$mode" == "dualboot" ]]; then
      # In dualboot: find the EXISTING Windows EFI partition, but never the
      # OSWORLDBOOT installer staging partition.
      EFI_PART=$(find_windows_efi_for_disk "$disk" || true)
      if [[ -z "$EFI_PART" ]]; then
        echo -e "${RED}[FAIL] Could not find existing Windows EFI partition on ${disk} or any other disk.${RESET}"
        exit 1
      fi
      if [[ "$EFI_PART" != *"${disk#/dev/}"* ]]; then
        echo -e "${YELLOW}[WARN] Using cross-disk EFI partition: ${EFI_PART}${RESET}"
      fi
    else
      # In wipe mode we know the exact partition numbers, but still prefer
      # labels when they are visible. Labels with spaces require awk to
      # reconstruct everything after the first field.
      EFI_PART=$(lsblk -rno NAME,PARTLABEL "$disk" 2>/dev/null | awk '{name=$1; $1=""; label=substr($0,2); gsub(/^[[:space:]]+|[[:space:]]+$/,"",label); if(label=="EFI System Partition") print "/dev/" name}' || true)
      [[ -z "$EFI_PART" && -b "$pred_efi" ]] && EFI_PART="$pred_efi"
    fi

    # CRITICAL: refuse to target the temporary OSWORLDBOOT ESP.
    if is_osworldboot_partition "${EFI_PART}"; then
      echo -e "${RED}[FAIL] Refusing to install GRUB to temporary OSWORLDBOOT partition (${EFI_PART}).${RESET}"
      exit 1
    fi

    ROOT_PART=$(lsblk -rno NAME,PARTLABEL "$disk" 2>/dev/null | awk '{name=$1; $1=""; label=substr($0,2); gsub(/^[[:space:]]+|[[:space:]]+$/,"",label); if(label=="Linux Root") print "/dev/" name}' || true)
    [[ -z "$ROOT_PART" && -b "$pred_root" ]] && ROOT_PART="$pred_root"

    HOME_PART=$(lsblk -rno NAME,PARTLABEL "$disk" 2>/dev/null | awk '{name=$1; $1=""; label=substr($0,2); gsub(/^[[:space:]]+|[[:space:]]+$/,"",label); if(label=="Linux Home") print "/dev/" name}' || true)
    [[ -z "$HOME_PART" && -b "$pred_home" ]] && HOME_PART="$pred_home"

    if [[ -n "$EFI_PART" && -n "$ROOT_PART" && -n "$HOME_PART" ]]; then
      break
    fi

    attempt=$((attempt + 1))
    if [[ $attempt -lt $max_attempts ]]; then
      echo -e "${YELLOW}[WARN] Partitions not visible yet, retrying... (${attempt}/${max_attempts})${RESET}"
      sleep 1
    fi
  done

  export EFI_PART ROOT_PART HOME_PART

  echo -e "${GREEN}[OK] EFI  partition: ${EFI_PART:-<not found>}${RESET}"
  echo -e "${GREEN}[OK] Root partition: ${ROOT_PART:-<not found>}${RESET}"
  echo -e "${GREEN}[OK] Home partition: ${HOME_PART:-<not found>}${RESET}"
}

format_and_mount_partitions() {
  # DEPRECATED: partition formatting and mounting is now handled by
  # bootstrap_system(). This wrapper remains as a compatibility shim that
  # validates the exported partition variables and guards against targeting
  # the temporary OSWORLDBOOT ESP.
  local install_mode="${1:-${mode:-wipe}}"

  echo ""
  echo -e "${BLUE}[INFO] Verifying target partition layout (formatting handled by bootstrap_system)...${RESET}"

  if [[ -z "${EFI_PART:-}" || -z "${ROOT_PART:-}" || -z "${HOME_PART:-}" ]]; then
    echo -e "${RED}[FAIL] One or more target partitions are not set.${RESET}"
    echo -e "${RED}[FAIL] EFI_PART=${EFI_PART:-<unset>} ROOT_PART=${ROOT_PART:-<unset>} HOME_PART=${HOME_PART:-<unset>}${RESET}"
    exit 1
  fi

  if is_osworldboot_partition "${EFI_PART}"; then
    echo -e "${RED}[FAIL] Refusing to install GRUB to temporary OSWORLDBOOT partition (${EFI_PART}).${RESET}"
    exit 1
  fi

  if [[ "$install_mode" == "dualboot" ]]; then
    echo -e "${YELLOW}[WARN] Dual-boot mode: reusing existing EFI partition ${EFI_PART}.${RESET}"
  fi

  echo -e "${GREEN}[OK] EFI  partition: ${EFI_PART}${RESET}"
  echo -e "${GREEN}[OK] Root partition: ${ROOT_PART}${RESET}"
  echo -e "${GREEN}[OK] Home partition: ${HOME_PART}${RESET}"
}
