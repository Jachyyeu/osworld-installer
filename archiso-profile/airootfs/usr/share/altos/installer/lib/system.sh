#!/bin/bash
set -euo pipefail

# ============================================================
# system.sh — System configuration inside chroot
# Designed to be sourced by install.sh
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh" 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$SCRIPT_DIR")"
ALTOS_DIR="$(dirname "$INSTALLER_DIR")"
PACKAGES_YAML="${ALTOS_DIR}/packages/basic.yaml"

# Mount point of the target system; install.sh may override this.
: "${ALTOS_MOUNT:=/mnt}"

configure_system() {
  local hostname="$1"
  local username="$2"
  local password="$3"
  local timezone="$4"
  local locale="$5"
  local keymap="$6"

  echo ""
  echo -e "${BLUE}[INFO] Configuring system settings...${RESET}"

  # Timezone
  echo -e "${BLUE}[INFO] Setting timezone to ${timezone}...${RESET}"
  run chroot "${ALTOS_MOUNT}" ln -sf "/usr/share/zoneinfo/${timezone}" /etc/localtime
  run chroot "${ALTOS_MOUNT}" hwclock --systohc

  # Locale
  echo -e "${BLUE}[INFO] Configuring locale: ${locale}...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would install glibc-langpack-${locale%%.*}${RESET}"
    echo -e "${BLUE}[DRY] Would run: localectl set-locale LANG=${locale}${RESET}"
  else
    run chroot "${ALTOS_MOUNT}" dnf install --assumeyes "glibc-langpack-${locale%%.*}"
    run chroot "${ALTOS_MOUNT}" localectl set-locale "LANG=${locale}"
    echo -e "${GREEN}[OK] Locale configured.${RESET}"
  fi

  # Console keymap
  echo -e "${BLUE}[INFO] Setting console keymap to ${keymap}...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would write KEYMAP=${keymap} to ${ALTOS_MOUNT}/etc/vconsole.conf${RESET}"
  else
    echo "KEYMAP=${keymap}" > "${ALTOS_MOUNT}/etc/vconsole.conf"
    echo -e "${GREEN}[OK] Keymap configured.${RESET}"
  fi

  # Hostname
  echo -e "${BLUE}[INFO] Setting hostname to ${hostname}...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would write ${hostname} to ${ALTOS_MOUNT}/etc/hostname${RESET}"
    echo -e "${BLUE}[DRY] Would write hosts entries to ${ALTOS_MOUNT}/etc/hosts${RESET}"
  else
    echo "$hostname" > "${ALTOS_MOUNT}/etc/hostname"

    cat > "${ALTOS_MOUNT}/etc/hosts" <<EOF
127.0.0.1   localhost
127.0.1.1   ${hostname}
::1         localhost
EOF
    echo -e "${GREEN}[OK] Hostname and hosts file configured.${RESET}"
  fi

  # User creation
  echo -e "${BLUE}[INFO] Creating user account: ${username}...${RESET}"
  run chroot "${ALTOS_MOUNT}" useradd -m -G wheel -s /bin/bash "$username"

  echo -e "${BLUE}[INFO] Setting password for ${username}...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would set password for user ${username}${RESET}"
  else
    echo "${username}:${password}" | run chroot "${ALTOS_MOUNT}" chpasswd
    echo -e "${GREEN}[OK] Password set.${RESET}"
  fi

  # Sudo
  echo -e "${BLUE}[INFO] Enabling sudo for the 'wheel' group...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would uncomment '%wheel ALL=(ALL:ALL) ALL' in ${ALTOS_MOUNT}/etc/sudoers${RESET}"
  else
    run sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "${ALTOS_MOUNT}/etc/sudoers"
    echo -e "${GREEN}[OK] Sudo enabled for wheel group.${RESET}"
  fi

  # Services
  echo -e "${BLUE}[INFO] Enabling essential services to start on boot...${RESET}"
  for svc in sddm NetworkManager bluetooth sshd; do
    run chroot "${ALTOS_MOUNT}" systemctl enable "${svc}.service"
  done

  echo -e "${GREEN}[OK] System configuration complete.${RESET}"
}

run_post_install_scripts() {
  local username="${1:-user}"

  echo ""
  echo -e "${BLUE}[INFO] Running post-install scripts...${RESET}"

  if [[ ! -f "$PACKAGES_YAML" ]]; then
    log_warn "packages/basic.yaml not found. Skipping post-install scripts."
    echo -e "${YELLOW}[WARN] packages/basic.yaml not found. Skipping post-install scripts.${RESET}"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would run post-install scripts from ${PACKAGES_YAML}${RESET}"
    return 0
  fi

  local chroot_dir="/var/lib/altos-install"
  mkdir -p "${ALTOS_MOUNT}${chroot_dir}"

  # Use Python to parse YAML, write scripts to temp files, and return their paths
  local script_list
  script_list=$(python3 <<PYEOF
import yaml, sys, os

try:
    with open("${PACKAGES_YAML}") as f:
        data = yaml.safe_load(f)
except Exception as e:
    print(f"[WARN] Failed to parse packages/basic.yaml: {e}", file=sys.stderr)
    sys.exit(0)

scripts = data.get("post_install_scripts", [])
if not scripts:
    print("[INFO] No post-install scripts defined.", file=sys.stderr)
    sys.exit(0)

for i, script in enumerate(scripts, 1):
    name = script.get("name", f"script-{i}")
    run_block = script.get("run", "")
    if not run_block:
        continue
    path = f"${chroot_dir}/post-{i:03d}.sh"
    with open(f"${ALTOS_MOUNT}{path}", "w") as f:
        f.write("#!/bin/bash\nset -e\n")
        f.write(f"export ALTOS_USERNAME='${username}'\n")
        f.write(f"# {name}\n")
        f.write(run_block)
        f.write("\n")
    os.chmod(f"${ALTOS_MOUNT}{path}", 0o755)
    print(path)
PYEOF
)

  if [[ -z "$script_list" ]]; then
    echo -e "${YELLOW}[WARN] No post-install scripts to run.${RESET}"
    return 0
  fi

  local total_count
  total_count=$(echo "$script_list" | wc -l)
  local current=0

  while IFS= read -r script_path; do
    [[ -z "$script_path" ]] && continue
    current=$((current + 1))
    echo -e "${BLUE}[INFO] Running post-install script ${current}/${total_count}${RESET}"
    if chroot "${ALTOS_MOUNT}" bash "$script_path"; then
      echo -e "${GREEN}[OK] Script ${current}/${total_count} completed.${RESET}"
    else
      echo -e "${YELLOW}[WARN] Script ${current}/${total_count} exited with an error (non-fatal).${RESET}"
    fi
  done <<< "$script_list"

  rm -rf "${ALTOS_MOUNT}${chroot_dir}"
  echo -e "${GREEN}[OK] Post-install scripts complete.${RESET}"
}

enable_services_from_yaml() {
  echo ""
  echo -e "${BLUE}[INFO] Enabling services from packages/basic.yaml...${RESET}"

  if [[ ! -f "$PACKAGES_YAML" ]]; then
    log_warn "packages/basic.yaml not found. Using default services only."
    echo -e "${YELLOW}[WARN] packages/basic.yaml not found. Using default services only.${RESET}"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would enable services from ${PACKAGES_YAML}${RESET}"
    return 0
  fi

  local services
  services=$(python3 -c "import yaml; data=yaml.safe_load(open('${PACKAGES_YAML}')); print('\n'.join(data.get('services',{}).get('enabled',[])))" 2>/dev/null || true)

  if [[ -z "$services" ]]; then
    echo -e "${YELLOW}[WARN] No services listed in packages/basic.yaml.${RESET}"
    return 0
  fi

  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    echo -e "${BLUE}[INFO] Enabling service: ${svc}${RESET}"
    chroot "${ALTOS_MOUNT}" systemctl enable "${svc}.service" 2>/dev/null || {
      echo -e "${YELLOW}[WARN] Failed to enable ${svc}.service (may not be installed yet).${RESET}"
    }
  done <<< "$services"

  echo -e "${GREEN}[OK] Services enabled.${RESET}"
}
