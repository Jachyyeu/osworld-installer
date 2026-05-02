#!/bin/bash
set -euo pipefail

# ============================================================
# lib/compatibility.sh — Hardware compatibility check
# Designed to be sourced by install.sh
# Runs BEFORE partitioning. Uses lspci and lsusb.
# ============================================================

if [[ -z "${GREEN:-}" ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  RESET='\033[0m'
fi

_compatibility_has_fail=false

_check_gpu() {
  echo ""
  echo -e "${BLUE}[INFO] Detecting GPU...${RESET}"

  local gpu_info
  gpu_info=$(lspci -nn | grep -iE 'VGA|3D|Display' || true)

  if [[ -z "$gpu_info" ]]; then
    echo -e "${YELLOW}[WARN] No GPU detected via lspci.${RESET}"
    return
  fi

  while IFS= read -r line; do
    if echo "$line" | grep -qi 'intel'; then
      echo -e "${GREEN}[OK] Intel GPU detected. Fully supported.${RESET}"
    elif echo "$line" | grep -qiE 'amd|ati|radeon'; then
      echo -e "${GREEN}[OK] AMD GPU detected. Open-source drivers included.${RESET}"
    elif echo "$line" | grep -qi 'nvidia'; then
      echo -e "${YELLOW}[WARN] NVIDIA GPU detected. Proprietary drivers will be installed automatically.${RESET}"
    else
      echo -e "${YELLOW}[WARN] Unknown GPU: ${line}${RESET}"
    fi
  done <<< "$gpu_info"

  # Optimus (dual GPU) check
  local intel_count nvidia_count
  intel_count=$(echo "$gpu_info" | grep -ci 'intel' || true)
  nvidia_count=$(echo "$gpu_info" | grep -ci 'nvidia' || true)
  if [[ "$intel_count" -ge 1 && "$nvidia_count" -ge 1 ]]; then
    echo -e "${YELLOW}[WARN] Optimus (Intel + NVIDIA) dual-GPU laptop detected.${RESET}"
    echo -e "${YELLOW}[WARN] You may need to configure PRIME after installation.${RESET}"
  fi
}

_check_wifi() {
  echo ""
  echo -e "${BLUE}[INFO] Detecting WiFi adapter...${RESET}"

  local wifi_info
  wifi_info=$(lspci -nn | grep -iE 'network|wireless|wifi' || true)
  if [[ -z "$wifi_info" ]]; then
    wifi_info=$(lsusb | grep -iE 'wireless|wifi|802.11|bluetooth' || true)
  fi

  if [[ -z "$wifi_info" ]]; then
    echo -e "${YELLOW}[WARN] No WiFi adapter detected.${RESET}"
    return
  fi

  while IFS= read -r line; do
    if echo "$line" | grep -qiE 'intel.*(ax200|ax210|wifi 6|8265|9260)'; then
      echo -e "${GREEN}[OK] Intel WiFi detected. linux-firmware includes drivers.${RESET}"
    elif echo "$line" | grep -qi 'broadcom'; then
      echo -e "${YELLOW}[WARN] Broadcom WiFi detected. May need manual firmware (broadcom-wl-dkms).${RESET}"
    elif echo "$line" | grep -qi 'realtek'; then
      local chip_id
      chip_id=$(echo "$line" | grep -oE '\[?[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]?' || true)
      echo -e "${BLUE}[INFO] Realtek WiFi detected (chip ${chip_id:-unknown}). Common, usually works.${RESET}"
    else
      echo -e "${BLUE}[INFO] WiFi adapter: ${line}${RESET}"
    fi
  done <<< "$wifi_info"
}

_check_storage() {
  local target_disk="${1:-}"

  echo ""
  echo -e "${BLUE}[INFO] Detecting storage...${RESET}"

  if [[ -n "$target_disk" ]]; then
    local disk_name
    disk_name=$(basename "$target_disk")
    local tran
    tran=$(lsblk -dno TRAN "/dev/$disk_name" 2>/dev/null || true)

    if [[ "$disk_name" =~ ^mmc ]]; then
      echo -e "${RED}[FAIL] eMMC storage detected on target disk (${target_disk}).${RESET}"
      echo -e "${RED}[FAIL] AltOS does not support eMMC. Install aborted.${RESET}"
      _compatibility_has_fail=true
      return
    fi

    case "$tran" in
      nvme)
        echo -e "${GREEN}[OK] NVMe storage detected. Fast and fully supported.${RESET}"
        ;;
      sata|ata|scsi)
        echo -e "${GREEN}[OK] SATA storage detected. Fully supported.${RESET}"
        ;;
      usb)
        echo -e "${YELLOW}[WARN] USB storage detected. Installation will work but may be slow.${RESET}"
        ;;
      *)
        echo -e "${BLUE}[INFO] Storage interface: ${tran:-unknown}${RESET}"
        ;;
    esac
  fi

  # Also scan all disks for eMMC
  local emmc_count
  emmc_count=$(lsblk -dno NAME | grep -cE '^mmc' || true)
  if [[ "$emmc_count" -gt 0 ]]; then
    echo -e "${YELLOW}[WARN] eMMC device(s) present in system (not target).${RESET}"
    echo -e "${YELLOW}[WARN] This is okay unless you intend to install to eMMC.${RESET}"
  fi
}

_check_audio() {
  echo ""
  echo -e "${BLUE}[INFO] Detecting audio controller...${RESET}"

  local audio_info
  audio_info=$(lspci -nn | grep -iE 'audio|sound|multimedia' || true)

  if [[ -z "$audio_info" ]]; then
    echo -e "${BLUE}[INFO] No PCI audio device detected. May be USB audio.${RESET}"
    return
  fi

  while IFS= read -r line; do
    if echo "$line" | grep -qi 'intel.*audio'; then
      echo -e "${GREEN}[OK] Intel HDA audio detected. Fully supported.${RESET}"
    else
      echo -e "${BLUE}[INFO] Audio controller: ${line}${RESET}"
    fi
  done <<< "$audio_info"
}

# --- Public API ---------------------------------------------

verify_compatibility() {
  local target_disk="${1:-}"

  echo ""
  echo -e "${BLUE}========================================${RESET}"
  echo -e "${BLUE}  HARDWARE COMPATIBILITY CHECK${RESET}"
  echo -e "${BLUE}========================================${RESET}"
  echo ""

  _check_gpu
  _check_wifi
  _check_storage "$target_disk"
  _check_audio

  echo ""
  echo -e "${BLUE}========================================${RESET}"

  if [[ "$_compatibility_has_fail" == true ]]; then
    echo -e "${RED}  COMPATIBILITY CHECK FAILED${RESET}"
    echo -e "${RED}========================================${RESET}"
    exit 1
  fi

  echo -e "${GREEN}  COMPATIBILITY CHECK PASSED${RESET}"
  echo -e "${GREEN}========================================${RESET}"
  echo ""
}
