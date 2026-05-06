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
    log_info "[DRY] Would run: $*"
    echo -e "${BLUE}[DRY] Would: $*${RESET}"
    return 0
  fi
  log_info "Running: $*"
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

  # Must be root (skipped in dry-run for testing)
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}[WARN] Skipping root check in dry-run mode.${RESET}"
  elif [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}[FAIL] This script must be run as root (use sudo).${RESET}"
    exit 1
  fi
  echo -e "${GREEN}[OK] Running as root.${RESET}"

  # UEFI only (skipped in dry-run for testing)
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}[WARN] Skipping UEFI check in dry-run mode.${RESET}"
  elif [[ ! -d /sys/firmware/efi/efivars ]]; then
    echo -e "${RED}[FAIL] UEFI mode not detected.${RESET}"
    echo -e "${RED}[FAIL] This installer only supports UEFI systems.${RESET}"
    exit 1
  fi
  echo -e "${GREEN}[OK] UEFI mode detected.${RESET}"

  # Internet connection (skipped in dry-run for testing)
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}[WARN] Skipping network check in dry-run mode.${RESET}"
  elif ! ping -c 1 -W 5 archlinux.org &>/dev/null; then
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

  # Export so subshells and independently-sourced libs see it
  export DRY_RUN

  # Source libraries — logging first so other libs can use it
  source "$LIB_DIR/logging.sh"
  source "$LIB_DIR/compatibility.sh"
  source "$LIB_DIR/disk.sh"
  source "$LIB_DIR/bootstrap.sh"
  source "$LIB_DIR/drivers.sh"
  source "$LIB_DIR/system.sh"
  source "$LIB_DIR/migration.sh"
  source "$LIB_DIR/bootloader.sh"

  # Start logging
  log_start

  # Step 1 — Environment verification
  verify_environment

  # Step 2 — Config parsing
  parse_config "/tmp/install-config.json"

  if [[ -z "${target_disk:-}" ]]; then
    log_error "target_disk is not set in configuration."
    exit 1
  fi

  check_mounted "$target_disk"

  # Step 3 — Hardware compatibility check
  verify_compatibility "$target_disk"

  echo ""
  echo -e "${BLUE}========================================${RESET}"
  echo -e "${BLUE}  INSTALLATION PLAN${RESET}"
  echo -e "${BLUE}========================================${RESET}"
  echo ""

  # Step 4 — Partition
  partition_disk "$target_disk" "$mode"

  # Step 5 — Detect partitions
  get_partitions "$target_disk"

  if [[ -z "${EFI_PART:-}" || -z "${ROOT_PART:-}" || -z "${HOME_PART:-}" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      echo -e "${YELLOW}[WARN] Partitions not found because this is a dry run. Using predicted paths.${RESET}"
      EFI_PART=$(get_partition_name "$target_disk" 1)
      ROOT_PART=$(get_partition_name "$target_disk" 2)
      HOME_PART=$(get_partition_name "$target_disk" 3)
    else
      log_error "Could not find all required partitions after partitioning."
      exit 1
    fi
  fi

  # Step 6 — Format & mount
  format_and_mount_partitions

  # Step 7 — Bootstrap base system
  bootstrap_system

  # Step 8 — Install hardware drivers
  install_drivers

  # Step 9 — System configuration
  configure_system "$hostname" "$username" "$password" "$timezone" "$locale" "$keymap"

  # Step 10 — Migrate Windows files (only in dual-boot mode)
  if [[ "$mode" == "dualboot" ]]; then
    migrate_windows_files "$target_disk" "$username"
  else
    log_info "Wipe mode selected. Skipping Windows file migration."
  fi

  # Step 11 — Enable first-boot wizard
  enable_first_boot_wizard

  # Step 12 — Bootloader
  install_bootloader

  # Step 13 — Setup recovery environment
  setup_recovery_environment

  # Step 14 — Finalize
  finalize_installation

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

enable_first_boot_wizard() {
  echo ""
  log_info "Enabling first-boot wizard..."

  local wizard_src_dir="${SCRIPT_DIR}/../first-boot"
  local wizard_dst_dir="/mnt/usr/share/altos/first-boot"
  local steps_dst_dir="${wizard_dst_dir}/steps"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY] Would copy first-boot wizard to target system."
    log_info "[DRY] Would create KDE autostart entry and systemd fallback."
    echo -e "${BLUE}[DRY] Would enable first-boot wizard.${RESET}"
    return 0
  fi

  if [[ ! -d "$wizard_src_dir" ]]; then
    log_warn "First-boot wizard source not found at $wizard_src_dir. Skipping."
    echo -e "${YELLOW}[WARN] First-boot wizard source not found. Skipping.${RESET}"
    return 0
  fi

  # Copy first-boot wizard and steps to target system
  mkdir -p "$wizard_dst_dir"
  cp -r "${wizard_src_dir}/"* "$wizard_dst_dir/" 2>/dev/null || true
  chmod +x "$wizard_dst_dir"/*.sh 2>/dev/null || true
  if [[ -d "$wizard_dst_dir/steps" ]]; then
    chmod +x "$wizard_dst_dir/steps"/*.sh 2>/dev/null || true
  fi
  log_info "First-boot wizard copied to target system."

  # Create KDE autostart entry in /etc/skel for new users
  local skel_autostart="/mnt/etc/skel/.config/autostart"
  mkdir -p "$skel_autostart"
  cat > "${skel_autostart}/altos-wizard.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=AltOS First Boot Wizard
Exec=/usr/share/altos/first-boot/wizard.sh
Icon=system-software-install
Terminal=true
Hidden=false
X-GNOME-Autostart-enabled=true
EOF

  # Also create for the current user if home exists
  local user_autostart="/mnt/home/${username}/.config/autostart"
  if [[ -d "/mnt/home/${username}" ]]; then
    mkdir -p "$user_autostart"
    cp "${skel_autostart}/altos-wizard.desktop" "${user_autostart}/altos-wizard.desktop"
    chown -R "${username}:${username}" "/mnt/home/${username}/.config" 2>/dev/null || true
  fi

  # Create systemd fallback service
  local systemd_dir="/mnt/etc/systemd/system"
  mkdir -p "$systemd_dir"
  cat > "${systemd_dir}/altos-first-boot.service" <<EOF
[Unit]
Description=AltOS First Boot Wizard
After=graphical-session.target network.target
ConditionPathExists=!/home/${username}/.config/altos/first-boot-done

[Service]
Type=oneshot
ExecStart=/usr/share/altos/first-boot/wizard.sh
User=${username}
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/${username}/.Xauthority

[Install]
WantedBy=graphical.target
EOF

  # Enable the systemd service as fallback
  arch-chroot /mnt systemctl enable altos-first-boot.service 2>/dev/null || true

  log_info "First-boot wizard enabled (KDE autostart + systemd fallback)."
  echo -e "${GREEN}[OK] First-boot wizard will run on first login.${RESET}"
}

setup_recovery_environment() {
  echo ""
  log_info "Setting up recovery environment..."

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY] Would copy recovery scripts and enable boot-failure detection."
    echo -e "${BLUE}[DRY] Would set up recovery environment.${RESET}"
    return 0
  fi

  local recovery_src="/usr/share/altos/recovery"
  local recovery_dst="/mnt/usr/share/altos/recovery"

  if [[ -d "$recovery_src" ]]; then
    mkdir -p "$recovery_dst"
    cp -r "$recovery_src/"* "$recovery_dst/" 2>/dev/null || true
    chmod +x "$recovery_dst/"*.sh 2>/dev/null || true
    log_info "Recovery scripts copied to target system."
    echo -e "${GREEN}[OK] Recovery scripts installed.${RESET}"
  else
    log_warn "Recovery scripts not found at $recovery_src. Skipping."
    echo -e "${YELLOW}[WARN] Recovery source not found. Skipping.${RESET}"
  fi

  # Create systemd service for boot-failure counting
  local systemd_dir="/mnt/etc/systemd/system"
  mkdir -p "$systemd_dir"

  cat > "$systemd_dir/altos-boot-monitor.service" <<'EOF'
[Unit]
Description=AltOS Boot Failure Monitor
After=systemd-user-sessions.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/altos-boot-monitor.sh
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
EOF

  # Boot monitor script
  mkdir -p /mnt/usr/local/bin
  cat > /mnt/usr/local/bin/altos-boot-monitor.sh <<'EOF'
#!/bin/bash
# Counts failed boots. If 3 failures in a row, sets flag for recovery boot.

COUNTER_FILE="/var/lib/altos/boot-failures"
RECOVERY_FLAG="/var/lib/altos/force-recovery"
SUCCESS_FLAG="/tmp/altos-boot-success"
MAX_FAILURES=3

mkdir -p /var/lib/altos

# If this script runs to completion, boot was successful
# A failed boot would not reach this point (service not started)
if [[ -f "$SUCCESS_FLAG" ]]; then
  # Previous boot succeeded, reset counter
  echo 0 > "$COUNTER_FILE"
  rm -f "$RECOVERY_FLAG"
else
  # Increment failure counter
  count=0
  [[ -f "$COUNTER_FILE" ]] && count=$(cat "$COUNTER_FILE")
  count=$((count + 1))
  echo "$count" > "$COUNTER_FILE"

  if [[ "$count" -ge "$MAX_FAILURES" ]]; then
    touch "$RECOVERY_FLAG"
    echo 0 > "$COUNTER_FILE"
  fi
fi

# Mark this boot as successful so far
touch "$SUCCESS_FLAG"
EOF
  chmod +x /mnt/usr/local/bin/altos-boot-monitor.sh

  # Enable the service in target system
  if [[ -d /mnt/etc/systemd/system ]]; then
    arch-chroot /mnt systemctl enable altos-boot-monitor.service 2>/dev/null || true
    log_info "Boot failure monitor enabled."
    echo -e "${GREEN}[OK] Recovery boot detection enabled.${RESET}"
  fi
}

finalize_installation() {
  echo ""
  log_info "Finalizing installation..."

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY] Would unmount all partitions and sync."
    echo -e "${BLUE}[DRY] Would unmount all partitions and sync.${RESET}"
    return 0
  fi

  # Ensure any pending writes are flushed
  sync

  # Copy install log to target system
  if [[ -f "$LOG_FILE_LIVE" && -d /mnt/home ]]; then
    local log_dst="/mnt/home/${username}/install.log"
    cp "$LOG_FILE_LIVE" "$log_dst" 2>/dev/null || true
    chown "${username}:${username}" "$log_dst" 2>/dev/null || true
    log_info "Install log copied to ${username}'s home directory."
  fi

  # Unmount everything
  umount -R /mnt/boot/efi 2>/dev/null || true
  umount -R /mnt/home 2>/dev/null || true
  umount -R /mnt 2>/dev/null || true

  log_ok "Installation finalized."
}

main "$@"
