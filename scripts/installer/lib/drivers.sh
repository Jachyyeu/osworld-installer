#!/bin/bash
set -euo pipefail

# ============================================================
# lib/drivers.sh — Automatic driver installation
# Designed to be sourced by install.sh
# Runs AFTER pacstrap, BEFORE bootloader.
# Detects hardware and installs correct drivers via pacman.
# ============================================================

if [[ -z "${GREEN:-}" ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  RESET='\033[0m'
fi

_log_driver() {
  local msg="$1"
  if command -v log_info &>/dev/null; then
    log_info "$msg"
  else
    echo -e "${BLUE}[INFO] ${msg}${RESET}"
  fi
}

_log_driver_warn() {
  local msg="$1"
  if command -v log_warn &>/dev/null; then
    log_warn "$msg"
  else
    echo -e "${YELLOW}[WARN] ${msg}${RESET}"
  fi
}

_log_driver_ok() {
  local msg="$1"
  if command -v log_ok &>/dev/null; then
    log_ok "$msg"
  else
    echo -e "${GREEN}[OK] ${msg}${RESET}"
  fi
}

_log_driver_error() {
  local msg="$1"
  if command -v log_error &>/dev/null; then
    log_error "$msg"
  else
    echo -e "${RED}[ERROR] ${msg}${RESET}"
  fi
}

_run_chroot() {
  if [[ "${DRY_RUN:-false}" == true ]]; then
    _log_driver "[DRY] Would run: arch-chroot /mnt $*"
    return 0
  fi
  if command -v log_cmd &>/dev/null; then
    log_cmd arch-chroot /mnt "$@"
  else
    arch-chroot /mnt "$@"
  fi
}

# --- Detectors ----------------------------------------------

_detect_gpu() {
  local gpu_info
  gpu_info=$(lspci -nn | grep -iE 'VGA|3D|Display' || true)

  if echo "$gpu_info" | grep -qi 'nvidia'; then
    echo "nvidia"
  elif echo "$gpu_info" | grep -qiE 'amd|ati|radeon'; then
    echo "amd"
  elif echo "$gpu_info" | grep -qi 'intel'; then
    echo "intel"
  else
    echo "unknown"
  fi
}

_detect_wifi() {
  local wifi_info
  wifi_info=$(lspci -nn | grep -iE 'network|wireless|wifi' || true)
  if [[ -z "$wifi_info" ]]; then
    wifi_info=$(lsusb | grep -iE 'wireless|wifi|802.11' || true)
  fi

  if echo "$wifi_info" | grep -qi 'broadcom'; then
    echo "broadcom"
  elif echo "$wifi_info" | grep -qi 'realtek'; then
    echo "realtek"
  elif echo "$wifi_info" | grep -qi 'intel'; then
    echo "intel"
  else
    echo "unknown"
  fi
}

_detect_realtek_chip() {
  local pci_info usb_info
  pci_info=$(lspci -nn | grep -i 'realtek' || true)
  usb_info=$(lsusb | grep -i 'realtek' || true)
  local combined="${pci_info}${usb_info}"

  if echo "$combined" | grep -qiE '8821|8821ce'; then
    echo "rtl8821ce-dkms"
  elif echo "$combined" | grep -qiE '88x2|8812|8822'; then
    echo "rtl88x2bu-dkms"
  elif echo "$combined" | grep -qiE '8188|8192|8723'; then
    echo "rtl88xxau-aircrack-dkms"
  else
    echo ""
  fi
}

# --- Installers ---------------------------------------------

_install_gpu_drivers() {
  local gpu
  gpu=$(_detect_gpu)

  echo ""
  _log_driver "Installing GPU drivers for: ${gpu}"

  case "$gpu" in
    nvidia)
      _log_driver "Installing NVIDIA proprietary drivers..."
      _run_chroot pacman -S --noconfirm nvidia-dkms nvidia-utils lib32-nvidia-utils
      _log_driver_ok "NVIDIA drivers installed."

      # Add kernel parameter for DRM modeset
      _log_driver "Enabling nvidia-drm.modeset=1 in GRUB..."
      if [[ "${DRY_RUN:-false}" == false ]]; then
        local grub_default="/mnt/etc/default/grub"
        if [[ -f "$grub_default" ]]; then
          if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_default"; then
            # Append to existing parameters
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia-drm.modeset=1"/' "$grub_default"
          else
            echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet nvidia-drm.modeset=1"' >> "$grub_default"
          fi
          _log_driver_ok "GRUB cmdline updated for NVIDIA."
        fi
      fi
      ;;

    amd)
      _log_driver "Installing AMD open-source drivers..."
      _run_chroot pacman -S --noconfirm mesa lib32-mesa vulkan-radeon
      _log_driver_ok "AMD drivers installed."
      ;;

    intel)
      _log_driver "Installing Intel open-source drivers..."
      _run_chroot pacman -S --noconfirm mesa lib32-mesa vulkan-intel
      _log_driver_ok "Intel drivers installed."
      ;;

    *)
      _log_driver_warn "Unknown GPU. Installing generic mesa drivers..."
      _run_chroot pacman -S --noconfirm mesa lib32-mesa
      _log_driver_ok "Generic mesa drivers installed."
      ;;
  esac
}

_install_wifi_drivers() {
  local wifi
  wifi=$(_detect_wifi)

  echo ""
  _log_driver "Installing WiFi drivers for: ${wifi}"

  case "$wifi" in
    broadcom)
      _log_driver "Installing Broadcom WiFi driver..."
      _run_chroot pacman -S --noconfirm broadcom-wl-dkms
      _log_driver_ok "Broadcom driver installed."
      ;;

    realtek)
      local pkg
      pkg=$(_detect_realtek_chip)
      if [[ -n "$pkg" ]]; then
        _log_driver "Installing Realtek WiFi driver: ${pkg}..."
        _run_chroot pacman -S --noconfirm "$pkg"
        _log_driver_ok "Realtek driver ${pkg} installed."
      else
        _log_driver_warn "Unknown Realtek chip. Skipping specific driver."
        _log_driver_warn "You may need to install a DKMS package manually after boot."
      fi
      ;;

    intel)
      _log_driver "Intel WiFi detected. linux-firmware already includes drivers."
      _log_driver_ok "No additional WiFi packages needed."
      ;;

    *)
      _log_driver_warn "Unknown WiFi adapter. Skipping specific driver installation."
      ;;
  esac
}

_regenerate_initramfs() {
  echo ""
  _log_driver "Regenerating initramfs..."
  _run_chroot mkinitcpio -P
  _log_driver_ok "Initramfs regenerated."
}

# --- Public API ---------------------------------------------

install_drivers() {
  echo ""
  echo -e "${BLUE}========================================${RESET}"
  echo -e "${BLUE}  AUTOMATIC DRIVER INSTALLATION${RESET}"
  echo -e "${BLUE}========================================${RESET}"
  echo ""

  _install_gpu_drivers
  _install_wifi_drivers
  _regenerate_initramfs

  echo ""
  echo -e "${GREEN}========================================${RESET}"
  echo -e "${GREEN}  DRIVER INSTALLATION COMPLETE${RESET}"
  echo -e "${GREEN}========================================${RESET}"
  echo ""
}
