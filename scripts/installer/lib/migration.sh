#!/bin/bash
set -euo pipefail

# ============================================================
# lib/migration.sh — Windows file migration
# Designed to be sourced by install.sh
# Runs after system configuration, before reboot.
# Only runs in dual-boot mode.
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh" 2>/dev/null || true

if [[ -z "${GREEN:-}" ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  RESET='\033[0m'
fi

_log_migrate() {
  local msg="$1"
  if command -v log_info &>/dev/null; then
    log_info "$msg"
  else
    echo -e "${BLUE}[INFO] ${msg}${RESET}"
  fi
}

_log_migrate_warn() {
  local msg="$1"
  if command -v log_warn &>/dev/null; then
    log_warn "$msg"
  else
    echo -e "${YELLOW}[WARN] ${msg}${RESET}"
  fi
}

_log_migrate_ok() {
  local msg="$1"
  if command -v log_ok &>/dev/null; then
    log_ok "$msg"
  else
    echo -e "${GREEN}[OK] ${msg}${RESET}"
  fi
}

# --- Helpers ------------------------------------------------

_find_windows_partition() {
  # Find the largest NTFS partition on the target disk
  local disk="$1"
  lsblk -rbno NAME,SIZE,FSTYPE "$disk" 2>/dev/null \
    | awk '$3=="ntfs" {print "/dev/" $1, $2}' \
    | sort -k2 -nr \
    | head -n1 \
    | awk '{print $1}'
}

_find_windows_user() {
  local win_mount="$1"
  local users_dir="${win_mount}/Users"

  if [[ ! -d "$users_dir" ]]; then
    echo ""
    return
  fi

  # Find the first non-system user directory
  find "$users_dir" -maxdepth 1 -mindepth 1 -type d \
    ! -name 'Public' \
    ! -name 'Default' \
    ! -name 'All Users' \
    ! -name 'Administrator' \
    | head -n1
}

_copy_standard_folders() {
  local src_dir="$1"
  local dst_dir="$2"

  local folders=(Documents Pictures Desktop Downloads Music Videos)

  for folder in "${folders[@]}"; do
    local src="${src_dir}/${folder}"
    local dst="${dst_dir}/${folder}"

    if [[ -d "$src" ]]; then
      _log_migrate "Copying ${folder}..."
      if [[ "${DRY_RUN:-false}" == true ]]; then
        _log_migrate "[DRY] Would copy ${src} → ${dst}"
      else
        mkdir -p "$dst"
        # Use rsync if available, otherwise cp -r
        if command -v rsync &>/dev/null; then
          rsync -a --progress "$src/" "$dst/" || _log_migrate_warn "Some files in ${folder} could not be copied."
        else
          cp -rT "$src" "$dst" || _log_migrate_warn "Some files in ${folder} could not be copied."
        fi
        # Fix ownership and permissions
        chown -R "${LINUX_USER}:${LINUX_USER}" "$dst" 2>/dev/null || true
        chmod -R u+rwX "$dst" 2>/dev/null || true
        _log_migrate_ok "${folder} copied."
      fi
    else
      _log_migrate "Folder ${folder} not found on Windows profile. Skipping."
    fi
  done
}

_copy_browser_bookmarks() {
  local win_user_dir="$1"
  local dst_dir="$2"
  local migrated_any=false

  mkdir -p "$dst_dir"

  # Firefox
  local firefox_profile
  firefox_profile=$(find "${win_user_dir}/AppData/Roaming/Mozilla/Firefox/Profiles" -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -n1 || true)
  if [[ -n "$firefox_profile" ]]; then
    _log_migrate "Copying Firefox bookmarks..."
    if [[ "${DRY_RUN:-false}" == true ]]; then
      _log_migrate "[DRY] Would copy Firefox profile data."
    else
      mkdir -p "${dst_dir}/firefox"
      cp -f "${firefox_profile}/places.sqlite" "${dst_dir}/firefox/" 2>/dev/null || true
      cp -f "${firefox_profile}/bookmarkbackups"/*.jsonlz4 "${dst_dir}/firefox/" 2>/dev/null || true
      chown -R "${LINUX_USER}:${LINUX_USER}" "${dst_dir}/firefox" 2>/dev/null || true
      _log_migrate_ok "Firefox bookmarks copied."
      migrated_any=true
    fi
  fi

  # Chrome / Edge (Chromium-based)
  local chrome_dirs=(
    "${win_user_dir}/AppData/Local/Google/Chrome/User Data/Default"
    "${win_user_dir}/AppData/Local/Microsoft/Edge/User Data/Default"
  )
  for chrome_dir in "${chrome_dirs[@]}"; do
    if [[ -f "${chrome_dir}/Bookmarks" ]]; then
      local browser_name
      if [[ "$chrome_dir" == *'Edge'* ]]; then
        browser_name="Edge"
      else
        browser_name="Chrome"
      fi
      _log_migrate "Copying ${browser_name} bookmarks..."
      if [[ "${DRY_RUN:-false}" == true ]]; then
        _log_migrate "[DRY] Would copy ${browser_name} Bookmarks file."
      else
        mkdir -p "${dst_dir}/${browser_name,,}"
        cp -f "${chrome_dir}/Bookmarks" "${dst_dir}/${browser_name,,}/" 2>/dev/null || true
        chown -R "${LINUX_USER}:${LINUX_USER}" "${dst_dir}/${browser_name,,}" 2>/dev/null || true
        _log_migrate_ok "${browser_name} bookmarks copied."
        migrated_any=true
      fi
    fi
  done

  if [[ "$migrated_any" == false ]]; then
    _log_migrate "No browser bookmarks found to migrate."
  fi
}

_copy_wifi_profiles() {
  local win_mount="$1"
  local dst_dir="$2"

  local wlan_profiles
  wlan_profiles=$(find "${win_mount}/ProgramData/Microsoft/Wlansvc/Profiles/Interfaces" -name '*.xml' 2>/dev/null || true)

  if [[ -z "$wlan_profiles" ]]; then
    _log_migrate "No Windows WiFi profiles found."
    return
  fi

  _log_migrate "Copying Windows WiFi profiles..."
  if [[ "${DRY_RUN:-false}" == true ]]; then
    _log_migrate "[DRY] Would copy WiFi profile XML files."
    return
  fi

  mkdir -p "${dst_dir}/wifi"
  local count=0
  while IFS= read -r profile; do
    cp -f "$profile" "${dst_dir}/wifi/" 2>/dev/null || continue
    ((count++)) || true
  done <<< "$wlan_profiles"

  chown -R "${LINUX_USER}:${LINUX_USER}" "${dst_dir}/wifi" 2>/dev/null || true

  if [[ "$count" -gt 0 ]]; then
    _log_migrate_ok "${count} WiFi profile(s) copied to ${dst_dir}/wifi/."
    _log_migrate_warn "Windows WiFi profiles are encrypted. You will need to re-enter passwords after boot."
  else
    _log_migrate "No WiFi profiles could be copied."
  fi
}

# --- Public API ---------------------------------------------

migrate_windows_files() {
  local target_disk="${1:-}"
  local linux_user="${2:-user}"

  LINUX_USER="$linux_user"

  echo ""
  echo -e "${BLUE}========================================${RESET}"
  echo -e "${BLUE}  WINDOWS FILE MIGRATION${RESET}"
  echo -e "${BLUE}========================================${RESET}"
  echo ""

  if [[ -z "$target_disk" ]]; then
    _log_migrate_warn "No target disk specified. Skipping migration."
    return 0
  fi

  local win_part
  win_part=$(_find_windows_partition "$target_disk")

  if [[ -z "$win_part" ]]; then
    _log_migrate_warn "No Windows NTFS partition found on ${target_disk}. Skipping migration."
    return 0
  fi

  _log_migrate "Found Windows partition: ${win_part}"

  local win_mount="/mnt/windows_temp"
  mkdir -p "$win_mount"

  _log_migrate "Mounting Windows partition read-only..."
  if [[ "${DRY_RUN:-false}" == true ]]; then
    _log_migrate "[DRY] Would mount ${win_part} → ${win_mount} (read-only)"
  else
    if ! mount -o ro "$win_part" "$win_mount"; then
      _log_migrate_warn "Failed to mount Windows partition. It may be hibernated or corrupted."
      rmdir "$win_mount" 2>/dev/null || true
      return 0
    fi

    # Verify the mount is actually read-only
    if grep -q " ${win_mount} .*\bro\b" /proc/mounts 2>/dev/null; then
      _log_migrate_ok "Windows partition mounted read-only."
    else
      _log_migrate_warn "Windows partition mount could not be verified as read-only. Proceeding with caution."
    fi
  fi

  local win_user_dir
  win_user_dir=$(_find_windows_user "$win_mount")

  if [[ -z "$win_user_dir" ]]; then
    _log_migrate_warn "Could not find a Windows user profile. Skipping file copy."
    if [[ "${DRY_RUN:-false}" == false ]]; then
      umount "$win_mount" || true
      rmdir "$win_mount" 2>/dev/null || true
    fi
    return 0
  fi

  local win_user_name
  win_user_name=$(basename "$win_user_dir")
  _log_migrate "Found Windows user profile: ${win_user_name}"

  local linux_home="/mnt/home/${linux_user}"
  local migrate_dst="${linux_home}/windows-migration"

  # Copy standard user folders
  _copy_standard_folders "$win_user_dir" "$linux_home"

  # Copy browser bookmarks
  _copy_browser_bookmarks "$win_user_dir" "${migrate_dst}/bookmarks"

  # Copy WiFi profiles
  _copy_wifi_profiles "$win_mount" "${migrate_dst}"

  # Create a README for the user
  if [[ "${DRY_RUN:-false}" == false ]]; then
    mkdir -p "$migrate_dst"
    cat > "${migrate_dst}/README.txt" <<EOF
Windows Migration Summary
=========================
Migrated from: ${win_user_name}
Windows partition: ${win_part}

Contents:
- Documents, Pictures, Desktop, Downloads, Music, Videos
  → copied to your Linux home folder
- Browser bookmarks
  → copied to windows-migration/bookmarks/
- WiFi profiles
  → copied to windows-migration/wifi/ (passwords must be re-entered)

Your Windows files are still safe on the NTFS partition.
EOF
    chown -R "${linux_user}:${linux_user}" "$migrate_dst" 2>/dev/null || true
    chmod -R u+rwX "$migrate_dst" 2>/dev/null || true
  fi

  # Unmount
  _log_migrate "Unmounting Windows partition..."
  if [[ "${DRY_RUN:-false}" == false ]]; then
    umount "$win_mount" || _log_migrate_warn "Failed to unmount ${win_mount} cleanly."
    rmdir "$win_mount" 2>/dev/null || true
    _log_migrate_ok "Windows partition unmounted."
  fi

  _log_migrate_ok "Windows migration complete."
  echo ""
}
