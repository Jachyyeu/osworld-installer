#!/bin/bash
set -uo pipefail

# AltOS Installer — automated end-to-end test loop
# Builds the ISO and runs the direct-kernel install + UEFI reboot test.
# Can loop multiple times or test multiple editions.
#
# Usage:
#   ./spam-e2e.sh                     # build ISO + run one full test
#   ./spam-e2e.sh --loop 3            # build ISO + run 3 full tests
#   ./spam-e2e.sh --editions home,gaming,creative,privacy  # test each edition once
#   ./spam-e2e.sh --skip-iso-build    # use existing ISO

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ISO_DIR="$PROJECT_DIR/out"
DISK="$SCRIPT_DIR/target-disk.img"
OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS="/usr/share/edk2/x64/OVMF_VARS.4m.fd"
KERNEL="/tmp/altos-iso-check/arch/boot/x86_64/vmlinuz-linux"
INITRD="/tmp/altos-iso-check/arch/boot/x86_64/initramfs-linux.img"

LOOP_COUNT=1
EDITIONS=""
SKIP_ISO_BUILD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --loop)
      LOOP_COUNT="$2"
      shift 2
      ;;
    --editions)
      EDITIONS="$2"
      LOOP_COUNT=0
      shift 2
      ;;
    --skip-iso-build)
      SKIP_ISO_BUILD=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -n "$EDITIONS" ]]; then
  IFS=',' read -ra EDITION_ARRAY <<< "$EDITIONS"
  LOOP_COUNT=${#EDITION_ARRAY[@]}
else
  EDITION_ARRAY=()
  for ((i=0; i<LOOP_COUNT; i++)); do
    EDITION_ARRAY+=("home")
  done
fi

find_iso() {
  ls -t "$ISO_DIR"/altos-*.iso 2>/dev/null | head -1
}

build_iso() {
  echo "[INFO] Building AltOS ISO..."
  cd "$PROJECT_DIR" || exit 1
  if ! command -v mkarchiso &>/dev/null; then
    echo "[FAIL] mkarchiso not found. Install archiso first."
    exit 1
  fi
  sudo mkarchiso -v -w /tmp/archiso-tmp -o "$ISO_DIR" "$PROJECT_DIR/archiso-profile/" 2>&1 | tee "$SCRIPT_DIR/mkarchiso-rebuild.log"
  local iso
  iso=$(find_iso)
  if [[ -z "$iso" ]]; then
    echo "[FAIL] ISO build did not produce output file."
    exit 1
  fi
  echo "[OK] Built ISO: $iso"
}

extract_iso_files() {
  local iso="$1"
  echo "[INFO] Extracting kernel/initrd from ISO..."
  rm -rf /tmp/altos-iso-check
  mkdir -p /tmp/altos-iso-check
  local mount_point=/tmp/altos-iso-check-mnt
  mkdir -p "$mount_point"
  sudo mount -o loop,ro "$iso" "$mount_point"
  cp "$mount_point"/arch/boot/x86_64/vmlinuz-linux /tmp/altos-iso-check/arch/boot/x86_64/vmlinuz-linux
  cp "$mount_point"/arch/boot/x86_64/archiso.img /tmp/altos-iso-check/arch/boot/x86_64/initramfs-linux.img
  sudo umount "$mount_point"
  rmdir "$mount_point" 2>/dev/null || true
  echo "[OK] ISO files extracted."
}

prepare_disk() {
  local edition="$1"
  if [[ ! -f "$DISK" ]]; then
    echo "[INFO] Creating fresh 26 GB disk image..."
    fallocate -l 26G "$DISK" || dd if=/dev/zero of="$DISK" bs=1M count=26624 status=progress
  fi

  # Write install-config.json for the live installer to pick up
  mkdir -p "$SCRIPT_DIR/mnt"
  cat > "$SCRIPT_DIR/install-config.json" <<EOF
{
  "install_type": "replace",
  "target_disk": "/dev/vda",
  "mode": "wipe",
  "hostname": "altos-vm",
  "username": "user",
  "password": "password123",
  "timezone": "UTC",
  "locale": "en_US.UTF-8",
  "keymap": "us",
  "edition": "$edition",
  "browser": "brave",
  "email_client": "thunderbird",
  "music_player": "strawberry",
  "include_office_suite": true
}
EOF
}

run_one_test() {
  local edition="$1"
  local run_num="$2"
  local install_log="$SCRIPT_DIR/spam-install-${edition}-${run_num}.log"
  local reboot_log="$SCRIPT_DIR/spam-reboot-${edition}-${run_num}.log"

  echo ""
  echo "========================================"
  echo "[RUN $run_num/$LOOP_COUNT] Edition: $edition"
  echo "========================================"

  prepare_disk "$edition"

  # Clean up any leftover QEMU
  if [[ -f "$SCRIPT_DIR/qemu.pid" ]]; then
    local pid
    pid=$(cat "$SCRIPT_DIR/qemu.pid" 2>/dev/null) || true
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      sleep 2
    fi
  fi

  # Phase 1: direct-kernel install
  rm -f "$install_log"
  echo "[INFO] Starting install phase..."
  qemu-system-x86_64 \
    -enable-kvm \
    -m 4096 \
    -smp 2 \
    -cpu host \
    -cdrom "$ISO" \
    -kernel "$KERNEL" \
    -initrd "$INITRD" \
    -append "archisobasedir=arch archisolabel=ALTOS_202606 console=ttyS0,115200 altos_skip_uefi_check" \
    -drive file="$DISK",format=raw,if=virtio \
    -serial file:"$install_log" \
    -display none \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
    > "$SCRIPT_DIR/spam-install-nohup-${edition}-${run_num}.out" 2>&1 &

  local install_pid=$!
  echo "$install_pid" > "$SCRIPT_DIR/qemu.pid"

  local install_ok=false
  local install_timeout=2400
  local install_elapsed=0
  while [[ $install_elapsed -lt $install_timeout ]]; do
    sleep 30
    install_elapsed=$((install_elapsed + 30))

    if [[ -f "$install_log" ]]; then
      if grep -iq "Installation complete" "$install_log" 2>/dev/null; then
        echo "[OK] Installation complete (${install_elapsed}s)"
        install_ok=true
        break
      fi
      if grep -q "Installation failed" "$install_log" 2>/dev/null; then
        echo "[FAIL] Installation failed (${install_elapsed}s)"
        break
      fi
      if (( install_elapsed % 120 == 0 )); then
        echo "=== $(date +%H:%M:%S) | elapsed ${install_elapsed}s | lines: $(wc -l < "$install_log") ==="
        tail -15 "$install_log" | grep -E "(FAIL|\[OK\]|pacstrap|grub-install|Post-install|first-boot)" || true
      fi
    fi

    if ! kill -0 "$install_pid" 2>/dev/null; then
      echo "[WARN] QEMU exited early after ${install_elapsed}s"
      break
    fi
  done

  kill "$install_pid" 2>/dev/null || true
  sleep 2
  kill -9 "$install_pid" 2>/dev/null || true
  wait "$install_pid" 2>/dev/null || true

  if [[ "$install_ok" != true ]]; then
    echo "[FAIL] Install phase failed for edition $edition"
    tail -80 "$install_log" 2>/dev/null || true
    return 1
  fi

  # Phase 2: UEFI reboot from disk
  cp "$OVMF_VARS" "$SCRIPT_DIR/ovmf_vars.fd"
  rm -f "$reboot_log"
  echo "[INFO] Starting reboot phase..."
  qemu-system-x86_64 \
    -enable-kvm \
    -m 4096 \
    -smp 2 \
    -cpu host \
    -drive file="$DISK",format=raw,if=virtio \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$SCRIPT_DIR/ovmf_vars.fd" \
    -serial file:"$reboot_log" \
    -display none \
    -vga none \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
    > "$SCRIPT_DIR/spam-reboot-nohup-${edition}-${run_num}.out" 2>&1 &

  local reboot_pid=$!
  echo "$reboot_pid" > "$SCRIPT_DIR/qemu.pid"

  local reboot_ok=false
  local reboot_timeout=300
  local reboot_elapsed=0
  while [[ $reboot_elapsed -lt $reboot_timeout ]]; do
    sleep 10
    reboot_elapsed=$((reboot_elapsed + 10))

    if [[ -f "$reboot_log" ]]; then
      if grep -qE " login:" "$reboot_log" 2>/dev/null; then
        echo "[OK] Login prompt found after reboot (${reboot_elapsed}s)"
        reboot_ok=true
        break
      fi
      if grep -q "Reached target Graphical Interface" "$reboot_log" 2>/dev/null; then
        echo "[OK] Graphical target reached after reboot (${reboot_elapsed}s)"
        reboot_ok=true
        break
      fi
    fi

    if ! kill -0 "$reboot_pid" 2>/dev/null; then
      echo "[WARN] Reboot QEMU exited early after ${reboot_elapsed}s"
      break
    fi
  done

  kill "$reboot_pid" 2>/dev/null || true
  sleep 2
  kill -9 "$reboot_pid" 2>/dev/null || true
  wait "$reboot_pid" 2>/dev/null || true

  if [[ "$reboot_ok" != true ]]; then
    echo "[FAIL] Reboot phase failed for edition $edition"
    tail -80 "$reboot_log" 2>/dev/null || true
    return 1
  fi

  echo "[SUCCESS] Run $run_num ($edition) passed."
  return 0
}

# Main
ISO=""
if [[ "$SKIP_ISO_BUILD" == false ]]; then
  build_iso
fi
ISO=$(find_iso)
if [[ -z "$ISO" ]]; then
  echo "[FAIL] No ISO found in $ISO_DIR"
  exit 1
fi
echo "[INFO] Using ISO: $ISO"
extract_iso_files "$ISO"

PASSED=0
FAILED=0
for ((i=0; i<LOOP_COUNT; i++)); do
  edition="${EDITION_ARRAY[$i]:-home}"
  if run_one_test "$edition" "$((i+1))"; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "========================================"
echo "SPAM E2E TEST SUMMARY"
echo "========================================"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "Total:  $LOOP_COUNT"

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
exit 0
