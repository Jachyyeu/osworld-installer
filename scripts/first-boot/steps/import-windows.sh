#!/bin/bash
set -euo pipefail

# ============================================================
# import-windows.sh — Import files from existing Windows install
# Only runs in dual-boot mode.
# ============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Detect if dualboot by looking for Windows partitions
find_windows_partition() {
  lsblk -rno NAME,FSTYPE,MOUNTPOINT 2>/dev/null | awk '$2=="ntfs" && $3=="" {print "/dev/" $1}' | head -n1
}

WINDOWS_PART=$(find_windows_partition)
MOUNT_POINT="/tmp/windows_import"
IMPORT_DEST="$HOME/windows-migration"

if [[ -z "$WINDOWS_PART" ]]; then
  echo -e "${YELLOW}[WARN] No unmounted Windows NTFS partition found.${RESET}"
  echo -e "${YELLOW}[WARN] Skipping Windows import. Are you in dual-boot mode?${RESET}"
  exit 0
fi

echo -e "${BLUE}[INFO] Found Windows partition: $WINDOWS_PART${RESET}"

# Create mount point
mkdir -p "$MOUNT_POINT"

# Mount read-only for safety
if ! mount -o ro "$WINDOWS_PART" "$MOUNT_POINT" 2>/dev/null; then
  echo -e "${YELLOW}[WARN] Could not mount Windows partition (may already be mounted elsewhere).${RESET}"
  exit 0
fi

# Find Windows user profile directory
WIN_USERS_DIR=$(find "$MOUNT_POINT" -maxdepth 2 -type d -name "Users" 2>/dev/null | head -n1)
if [[ -z "$WIN_USERS_DIR" ]]; then
  echo -e "${YELLOW}[WARN] Could not find Users directory on Windows partition.${RESET}"
  umount "$MOUNT_POINT" || true
  exit 0
fi

# Try to find the primary user (non-Public, non-Default)
WIN_USER_DIR=$(find "$WIN_USERS_DIR" -maxdepth 1 -type d ! -name "Users" ! -name "Public" ! -name "Default" ! -name "All Users" 2>/dev/null | head -n1)
if [[ -z "$WIN_USER_DIR" ]]; then
  WIN_USER_DIR="$WIN_USERS_DIR/Public"
fi

echo -e "${BLUE}[INFO] Windows user profile: $WIN_USER_DIR${RESET}"

# Interactive checklist
echo ""
echo -e "${BLUE}Select items to import (answer y/n for each):${RESET}"

import_items=()

ask_import() {
  local name="$1"
  local path="$2"
  local answer
  read -rp "$(echo -e "${BLUE}[?]${RESET} Import $name? [y/N]: ")" answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    import_items+=("$name|$path")
  fi
}

ask_import "Documents" "$WIN_USER_DIR/Documents"
ask_import "Pictures"  "$WIN_USER_DIR/Pictures"
ask_import "Desktop"   "$WIN_USER_DIR/Desktop"
ask_import "Downloads" "$WIN_USER_DIR/Downloads"
ask_import "Music"     "$WIN_USER_DIR/Music"
ask_import "Videos"    "$WIN_USER_DIR/Videos"
ask_import "Bookmarks (Firefox/Chrome/Edge)" "BOOKMARKS"
ask_import "WiFi passwords" "WIFI"

if [[ ${#import_items[@]} -eq 0 ]]; then
  echo -e "${YELLOW}[SKIP] No items selected for import.${RESET}"
  umount "$MOUNT_POINT" || true
  exit 0
fi

# Create destination
mkdir -p "$IMPORT_DEST"

echo ""
echo -e "${BLUE}[INFO] Starting import...${RESET}"

for item in "${import_items[@]}"; do
  name="${item%%|*}"
  path="${item#*|}"

  echo -e "${BLUE}[INFO] Importing $name...${RESET}"

  if [[ "$path" == "BOOKMARKS" ]]; then
    # Firefox bookmarks
    ff_src="$WIN_USER_DIR/AppData/Roaming/Mozilla/Firefox/Profiles"
    if [[ -d "$ff_src" ]]; then
      mkdir -p "$IMPORT_DEST/bookmarks"
      find "$ff_src" -name "places.sqlite" -exec cp {} "$IMPORT_DEST/bookmarks/firefox_places.sqlite" \; 2>/dev/null || true
      echo -e "${GREEN}[OK] Firefox bookmarks copied.${RESET}"
    fi
    # Chrome bookmarks
    chrome_src="$WIN_USER_DIR/AppData/Local/Google/Chrome/User Data/Default"
    if [[ -d "$chrome_src" ]]; then
      cp "$chrome_src/Bookmarks" "$IMPORT_DEST/bookmarks/chrome_bookmarks.json" 2>/dev/null || true
      echo -e "${GREEN}[OK] Chrome bookmarks copied.${RESET}"
    fi
    # Edge bookmarks
    edge_src="$WIN_USER_DIR/AppData/Local/Microsoft/Edge/User Data/Default"
    if [[ -d "$edge_src" ]]; then
      cp "$edge_src/Bookmarks" "$IMPORT_DEST/bookmarks/edge_bookmarks.json" 2>/dev/null || true
      echo -e "${GREEN}[OK] Edge bookmarks copied.${RESET}"
    fi
  elif [[ "$path" == "WIFI" ]]; then
    # WiFi profiles (XML)
    wifi_src="$MOUNT_POINT/ProgramData/Microsoft/Wlansvc/Profiles/Interfaces"
    if [[ -d "$wifi_src" ]]; then
      mkdir -p "$IMPORT_DEST/wifi"
      find "$wifi_src" -name "*.xml" -exec cp {} "$IMPORT_DEST/wifi/" \; 2>/dev/null || true
      echo -e "${GREEN}[OK] WiFi profiles copied (passwords may need re-entry).${RESET}"
    fi
  else
    if [[ -d "$path" ]]; then
      dest_name=$(basename "$path")
      rsync -a --info=progress2 "$path/" "$IMPORT_DEST/$dest_name/" 2>/dev/null || cp -r "$path" "$IMPORT_DEST/" 2>/dev/null || true
      echo -e "${GREEN}[OK] $name imported.${RESET}"
    else
      echo -e "${YELLOW}[WARN] $name not found on Windows partition.${RESET}"
    fi
  fi
done

# Unmount
umount "$MOUNT_POINT" || true
rmdir "$MOUNT_POINT" 2>/dev/null || true

# Fix ownership
chown -R "$USER:$USER" "$IMPORT_DEST" 2>/dev/null || true

echo ""
echo -e "${GREEN}[OK] Windows import complete. Files saved to: $IMPORT_DEST${RESET}"
