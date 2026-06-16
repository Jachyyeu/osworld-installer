#!/bin/bash
set -euo pipefail

# ============================================================
# secureboot.sh — Secure Boot MOK enrollment for AltOS
# Called by install.sh after the base system is installed.
# Handles: signing rEFInd + kernel, enrolling MOK, pacman hook.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging.sh"

# --- Configuration ------------------------------------------
# These paths are set by install.sh before calling this script
: "${ALTOS_MOUNT:=/mnt}"
: "${EFI_PARTITION:=/boot/efi}"
: "${STAGING_DIR:=/tmp/secureboot}"

MOK_KEY="${STAGING_DIR}/MOK.key"
MOK_CRT="${STAGING_DIR}/MOK.crt"
MOK_CER="${STAGING_DIR}/MOK.cer"
REFIND_EFI="${EFI_PARTITION}/EFI/refind/refind_x64.efi"

# ============================================================
# Main entry
# ============================================================

setup_secure_boot() {
  info "Starting Secure Boot setup (MOK enrollment strategy)..."

  # 1) Verify staging files exist
  if [[ ! -f "${STAGING_DIR}/enrollment-needed" ]]; then
    info "No enrollment-needed flag found. Skipping Secure Boot setup."
    return 0
  fi

  if [[ ! -f "${MOK_KEY}" ]] || [[ ! -f "${MOK_CRT}" ]]; then
    error "MOK keypair missing in ${STAGING_DIR}. Cannot set up Secure Boot."
    return 1
  fi

  # 2) Install signing tools into the chroot if not present
  info "Installing sbsigntools and mokutil into target system..."
  pacman -Sy --noconfirm -r "${ALTOS_MOUNT}" sbsigntools mokutil openssl

  # 3) Sign the rEFInd EFI binary
  #    The unsigned binary was copied by the normal bootloader install.
  #    We overwrite it with a signed version so shim will accept it.
  info "Signing rEFInd EFI binary..."
  if [[ -f "${REFIND_EFI}" ]]; then
    arch-chroot "${ALTOS_MOUNT}" sbsign \
      --key "${MOK_KEY}" \
      --cert "${MOK_CRT}" \
      --output "${REFIND_EFI}" \
      "${REFIND_EFI}"
    ok "rEFInd signed successfully."
  else
    warn "rEFInd EFI binary not found at ${REFIND_EFI} — skipping rEFInd signing."
  fi

  # 4) Copy signed rEFInd to EFI/BOOT/grubx64.efi
  #    shim looks for a second-stage loader in the same directory.
  #    By naming it grubx64.efi, shim will chainload it automatically.
  local grubx64="${EFI_PARTITION}/EFI/BOOT/grubx64.efi"
  if [[ -f "${REFIND_EFI}" ]]; then
    info "Copying signed rEFInd to EFI/BOOT/grubx64.efi for shim chainload..."
    cp -f "${REFIND_EFI}" "${grubx64}"
    ok "shim second-stage placed at ${grubx64}."
  fi

  # 5) Sign the kernel
  #    The Arch kernel is unsigned by default.  We sign it with our MOK
  #    so shim → rEFInd → signed-kernel works end-to-end.
  info "Signing Linux kernel..."
  local kernel="${ALTOS_MOUNT}/boot/vmlinuz-linux"
  if [[ -f "${kernel}" ]]; then
    arch-chroot "${ALTOS_MOUNT}" sbsign \
      --key "${MOK_KEY}" \
      --cert "${MOK_CRT}" \
      --output "${kernel}" \
      "${kernel}"
    ok "Kernel signed successfully."
  else
    warn "Kernel not found at ${kernel} — skipping kernel signing."
  fi

  # 6) Schedule MOK enrollment via mokutil
  #    This writes the certificate into the EFI variable store.
  #    On the *next* boot, MokManager will prompt the user to enroll it.
  info "Scheduling MOK certificate enrollment..."
  arch-chroot "${ALTOS_MOUNT}" mokutil --import "${MOK_CER}" || true
  ok "MOK enrollment scheduled.  User will be prompted on next boot."

  # 7) Copy MOK files into the installed system for future use
  #    (kernel updates, new EFI binaries, etc.)
  local sys_sb_dir="${ALTOS_MOUNT}/etc/altos/secureboot"
  mkdir -p "${sys_sb_dir}"
  cp -f "${MOK_KEY}" "${sys_sb_dir}/MOK.key"
  cp -f "${MOK_CRT}" "${sys_sb_dir}/MOK.crt"
  cp -f "${MOK_CER}" "${sys_sb_dir}/MOK.cer"
  chmod 600 "${sys_sb_dir}/MOK.key"
  ok "MOK keypair copied to ${sys_sb_dir}."

  # 8) Install the pacman hook for auto-signing on kernel updates
  install_pacman_sign_hook

  # 9) Create the MokManager walkthrough marker
  #    The first-boot wizard checks for this and shows friendly instructions.
  touch "${ALTOS_MOUNT}/var/lib/altos/mok-enrollment-pending"
  ok "MokManager walkthrough marker created."

  info "Secure Boot setup complete.  Chain: shim → rEFInd → signed-kernel"
}

# ============================================================
# Pacman hook — auto-sign kernel after every update
# ============================================================

install_pacman_sign_hook() {
  info "Installing pacman hook for kernel auto-signing..."

  local hook_dir="${ALTOS_MOUNT}/etc/pacman.d/hooks"
  mkdir -p "${hook_dir}"

  cat > "${hook_dir}/99-altos-sign.hook" <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Path
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Signing kernel with AltOS MOK for Secure Boot...
When = PostTransaction
Exec = /usr/local/bin/altos-sign-kernel.sh
NeedsTargets
EOF

  local sign_script="${ALTOS_MOUNT}/usr/local/bin/altos-sign-kernel.sh"
  mkdir -p "${ALTOS_MOUNT}/usr/local/bin"

  cat > "${sign_script}" <<'EOF'
#!/bin/bash
set -e

KEY="/etc/altos/secureboot/MOK.key"
CRT="/etc/altos/secureboot/MOK.crt"

if [[ ! -f "${KEY}" ]] || [[ ! -f "${CRT}" ]]; then
  echo "AltOS MOK keypair missing — skipping kernel signing."
  exit 0
fi

for kernel in /boot/vmlinuz-linux; do
  if [[ -f "${kernel}" ]]; then
    echo "Signing ${kernel}..."
    sbsign --key "${KEY}" --cert "${CRT}" --output "${kernel}" "${kernel}"
  fi
done
EOF

  chmod +x "${sign_script}"
  ok "Pacman hook installed at ${hook_dir}/99-altos-sign.hook"
}

# ============================================================
# MokManager first-boot walkthrough text
# ============================================================

print_mok_walkthrough() {
  cat <<'EOF'

╔══════════════════════════════════════════════════════════════╗
║           AltOS Secure Boot — One-Time Setup                 ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  AltOS needs to register a security key with your PC.        ║
║  This is normal, safe, and only takes a minute.              ║
║                                                              ║
║  1. On the next screen, select  Enroll MOK                   ║
║  2. Select  Continue                                         ║
║  3. Select  Yes  to enroll the key                           ║
║  4. Enter the password you just created                      ║
║  5. Select  Reboot                                           ║
║                                                              ║
║  After rebooting, Secure Boot stays ON and AltOS will        ║
║  start normally every time.                                  ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

EOF
}

# ============================================================
# Run if executed directly
# ============================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_secure_boot
fi
