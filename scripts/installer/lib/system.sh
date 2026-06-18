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
ALTOS_EDITION="${ALTOS_EDITION:-home}"
PACKAGES_YAML="${ALTOS_DIR}/packages/${ALTOS_EDITION}.yaml"

# Fall back to basic.yaml if the edition-specific file does not exist
if [[ ! -f "$PACKAGES_YAML" ]]; then
  PACKAGES_YAML="${ALTOS_DIR}/packages/basic.yaml"
fi

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
  run ln -sf "/usr/share/zoneinfo/${timezone}" /mnt/etc/localtime
  run arch-chroot /mnt hwclock --systohc

  # Locale
  echo -e "${BLUE}[INFO] Configuring locale: ${locale}...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would uncomment ${locale} in /mnt/etc/locale.gen${RESET}"
    echo -e "${BLUE}[DRY] Would run: locale-gen${RESET}"
    echo -e "${BLUE}[DRY] Would create /mnt/etc/locale.conf with LANG=${locale}${RESET}"
  else
    if grep -q "^#${locale}" /mnt/etc/locale.gen; then
      run sed -i "s/^#${locale}/${locale}/" /mnt/etc/locale.gen
      echo -e "${GREEN}[OK] Uncommented ${locale} in locale.gen.${RESET}"
    fi
    run arch-chroot /mnt locale-gen
    echo "LANG=${locale}" > /mnt/etc/locale.conf
    echo -e "${GREEN}[OK] Locale configured.${RESET}"
  fi

  # Console keymap
  echo -e "${BLUE}[INFO] Setting console keymap to ${keymap}...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would write KEYMAP=${keymap} to /mnt/etc/vconsole.conf${RESET}"
  else
    echo "KEYMAP=${keymap}" > /mnt/etc/vconsole.conf
    echo -e "${GREEN}[OK] Keymap configured.${RESET}"
  fi

  # Hostname
  echo -e "${BLUE}[INFO] Setting hostname to ${hostname}...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would write ${hostname} to /mnt/etc/hostname${RESET}"
    echo -e "${BLUE}[DRY] Would write hosts entries to /mnt/etc/hosts${RESET}"
  else
    echo "$hostname" > /mnt/etc/hostname

    cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   ${hostname}
::1         localhost
EOF
    echo -e "${GREEN}[OK] Hostname and hosts file configured.${RESET}"
  fi

  # User creation
  echo -e "${BLUE}[INFO] Creating user account: ${username}...${RESET}"
  run arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$username"

  echo -e "${BLUE}[INFO] Setting password for ${username}...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would set password for user ${username}${RESET}"
  else
    run arch-chroot /mnt chpasswd <<< "${username}:${password}"
    echo -e "${GREEN}[OK] Password set.${RESET}"
  fi

  # Sudo
  echo -e "${BLUE}[INFO] Enabling sudo for the 'wheel' group...${RESET}"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${BLUE}[DRY] Would uncomment '%wheel ALL=(ALL:ALL) ALL' in /mnt/etc/sudoers${RESET}"
  else
    run sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers
    echo -e "${GREEN}[OK] Sudo enabled for wheel group.${RESET}"
  fi

  # NetworkManager
  echo -e "${BLUE}[INFO] Enabling NetworkManager to start on boot...${RESET}"
  run arch-chroot /mnt systemctl enable NetworkManager.service

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
  mkdir -p "/mnt${chroot_dir}"

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
    with open(f"/mnt{path}", "w") as f:
        f.write("#!/bin/bash\nset -e\n")
        f.write(f"export ALTOS_USERNAME='${username}'\n")
        f.write(f"# {name}\n")
        f.write(run_block)
        f.write("\n")
    os.chmod(f"/mnt{path}", 0o755)
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
    if arch-chroot /mnt bash "$script_path"; then
      echo -e "${GREEN}[OK] Script ${current}/${total_count} completed.${RESET}"
    else
      echo -e "${YELLOW}[WARN] Script ${current}/${total_count} exited with an error (non-fatal).${RESET}"
    fi
  done <<< "$script_list"

  rm -rf "/mnt${chroot_dir:?}"
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
    arch-chroot /mnt systemctl enable "${svc}.service" 2>/dev/null || {
      echo -e "${YELLOW}[WARN] Failed to enable ${svc}.service (may not be installed yet).${RESET}"
    }
  done <<< "$services"

  echo -e "${GREEN}[OK] Services enabled.${RESET}"
}
