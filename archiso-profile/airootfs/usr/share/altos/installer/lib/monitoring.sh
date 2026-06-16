#!/bin/bash
set -euo pipefail

# ============================================================
# monitoring.sh — Optional remote monitoring setup
# Configures the target system to upload screenshots or
# maintain a reverse SSH tunnel to an observer host.
# Designed to be sourced by install.sh
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh" 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

setup_monitoring() {
  local username="${1:-user}"

  echo ""
  echo -e "${BLUE}[INFO] Setting up optional remote monitoring...${RESET}"

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would configure remote monitoring.${RESET}"
    return 0
  fi

  # Monitoring config: read from install-config.json if present
  local monitor_host monitor_user monitor_path
  monitor_host=$(python3 -c "import json; print(json.load(open('/tmp/install-config.json')).get('monitor_host',''))" 2>/dev/null || true)
  monitor_user=$(python3 -c "import json; print(json.load(open('/tmp/install-config.json')).get('monitor_user',''))" 2>/dev/null || true)
  monitor_path=$(python3 -c "import json; print(json.load(open('/tmp/install-config.json')).get('monitor_path',''))" 2>/dev/null || true)

  if [[ -z "$monitor_host" || -z "$monitor_user" || -z "$monitor_path" ]]; then
    log_info "Remote monitoring not configured (monitor_host/user/path missing from config). Skipping."
    echo -e "${YELLOW}[WARN] Remote monitoring not configured. Skipping.${RESET}"
    return 0
  fi

  # Generate SSH key pair for the target user
  local user_home="/mnt/home/${username}"
  mkdir -p "${user_home}/.ssh"
  if [[ ! -f "${user_home}/.ssh/altos_monitor" ]]; then
    arch-chroot /mnt ssh-keygen -t ed25519 -f "/home/${username}/.ssh/altos_monitor" -N "" -C "altos-monitor@${username}"
    echo -e "${GREEN}[OK] Generated monitor SSH key for ${username}.${RESET}"
  fi

  # Write monitoring config
  mkdir -p /mnt/etc/altos
  cat > /mnt/etc/altos/monitor.conf <<EOF
DEST_HOST="${monitor_host}"
DEST_USER="${monitor_user}"
DEST_PATH="${monitor_path}"
EOF

  # Copy monitor script and service to target
  local monitor_script="${SCRIPT_DIR}/../first-boot/altos-monitor.sh"
  local monitor_service="${SCRIPT_DIR}/../first-boot/altos-monitor.service"

  if [[ -f "$monitor_script" ]]; then
    mkdir -p /mnt/usr/share/altos/first-boot
    cp "$monitor_script" /mnt/usr/share/altos/first-boot/
    chmod +x /mnt/usr/share/altos/first-boot/altos-monitor.sh
  fi

  if [[ -f "$monitor_service" ]]; then
    mkdir -p /mnt/home/${username}/.config/systemd/user
    cp "$monitor_service" /mnt/home/${username}/.config/systemd/user/
    arch-chroot /mnt chown -R "${username}:${username}" "/home/${username}/.config"
  fi

  log_info "Remote monitoring configured for ${monitor_user}@${monitor_host}:${monitor_path}"
  echo -e "${GREEN}[OK] Remote monitoring configured.${RESET}"
}
