#!/bin/bash
set -euo pipefail

# ============================================================
# lib/drivers.sh — Automatic driver installation for Fedora
# Designed to be sourced by install.sh
# Runs AFTER bootstrap, BEFORE bootloader.
# Detects hardware and installs correct drivers via dnf + RPMFusion.
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh" 2>/dev/null || true

if [[ -z "${GREEN:-}" ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  RESET='\033[0m'
fi

_log_driver() {
  local msg="$1"
  if command -v log_info >/dev/null 2>&1; then
    log_info "$msg"
  else
    echo -e "${BLUE}[INFO] ${msg}${RESET}"
  fi
}

_log_driver_warn() {
  local msg="$1"
  if command -v log_warn >/dev/null 2>&1; then
    log_warn "$msg"
  else
    echo -e "${YELLOW}[WARN] ${msg}${RESET}"
  fi
}

_log_driver_ok() {
  local msg="$1"
  if command -v log_ok >/dev/null 2>&1; then
    log_ok "$msg"
  else
    echo -e "${GREEN}[OK] ${msg}${RESET}"
  fi
}

_run_chroot() {
  if [[ "${DRY_RUN:-false}" == true ]]; then
    _log_driver "[DRY] Would run: chroot /mnt $*"
    return 0
  fi
  if command -v log_cmd >/dev/null 2>&1; then
    log_cmd chroot /mnt "$@"
  else
    chroot /mnt "$@"
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
    echo "akmod-rtl8821ce"
  elif echo "$combined" | grep -qiE '88x2|8812|8822'; then
    echo "akmod-rtl88x2bu"
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
      _run_chroot dnf install --assumeyes akmod-nvidia xorg-x11-drv-nvidia-cuda || {
        _log_driver_warn "NVIDIA akmod install failed; falling back to nouveau."
        _run_chroot dnf install --assumeyes xorg-x11-drv-nouveau
      }
      _log_driver_ok "NVIDIA driver setup complete."

      # Add kernel parameter for DRM modeset
      _log_driver "Enabling nvidia-drm.modeset=1 in GRUB..."
      if [[ "${DRY_RUN:-false}" == false ]]; then
        local grub_default="/mnt/etc/default/grub"
        if [[ -f "$grub_default" ]]; then
          if grep -q 'nvidia-drm.modeset=1' "$grub_default"; then
            _log_driver "nvidia-drm.modeset=1 already present in GRUB config. Skipping."
          elif grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_default"; then
            run sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia-drm.modeset=1"/' "$grub_default"
            _log_driver_ok "GRUB cmdline updated for NVIDIA."
          else
            echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet nvidia-drm.modeset=1"' >> "$grub_default"
            _log_driver_ok "GRUB cmdline updated for NVIDIA."
          fi
        fi
      fi
      ;;

    amd)
      _log_driver "Installing AMD open-source drivers..."
      _run_chroot dnf install --assumeyes mesa vulkan-loader vulkan-radeon
      _log_driver_ok "AMD drivers installed."
      ;;

    intel)
      _log_driver "Installing Intel open-source drivers..."
      _run_chroot dnf install --assumeyes mesa vulkan-loader vulkan-intel
      _log_driver_ok "Intel drivers installed."
      ;;

    *)
      _log_driver_warn "Unknown GPU. Ensuring generic mesa drivers are present..."
      _run_chroot dnf install --assumeyes mesa
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
      _run_chroot dnf install --assumeyes akmod-wl || {
        _log_driver_warn "akmod-wl install failed; WiFi may not work after boot."
      }
      _log_driver_ok "Broadcom driver install attempted."
      ;;

    realtek)
      local pkg
      pkg=$(_detect_realtek_chip)
      if [[ -n "$pkg" ]]; then
        _log_driver "Installing Realtek WiFi driver: ${pkg}..."
        _run_chroot dnf install --assumeyes "$pkg" || {
          _log_driver_warn "${pkg} install failed; WiFi may not work after boot."
        }
        _log_driver_ok "Realtek driver ${pkg} install attempted."
      else
        _log_driver_warn "Unknown Realtek chip. Skipping specific driver."
        _log_driver_warn "You may need to install an akmod package manually after boot."
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
  _run_chroot dracut -f
  _log_driver_ok "Initramfs regenerated."
}

# --- Public API ---------------------------------------------

_enable_rpmfusion() {
  if [[ "${DRY_RUN:-false}" == true ]]; then
    _log_driver "[DRY] Would enable RPMFusion free and nonfree repositories."
    return 0
  fi

  _log_driver "Enabling RPMFusion repositories..."
  _run_chroot dnf install --assumeyes \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-42.noarch.rpm" \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-42.noarch.rpm" || {
    _log_driver_warn "Failed to enable RPMFusion. Proprietary drivers may not install."
    return 0
  }
  _log_driver_ok "RPMFusion enabled."
}

install_drivers() {
  echo ""
  echo -e "${BLUE}========================================${RESET}"
  echo -e "${BLUE}  AUTOMATIC DRIVER INSTALLATION${RESET}"
  echo -e "${BLUE}========================================${RESET}"
  echo ""

  _enable_rpmfusion
  _install_gpu_drivers
  _install_wifi_drivers
  _regenerate_initramfs

  echo ""
  echo -e "${GREEN}========================================${RESET}"
  echo -e "${GREEN}  DRIVER INSTALLATION COMPLETE${RESET}"
  echo -e "${GREEN}========================================${RESET}"
  echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  install_drivers
fi
