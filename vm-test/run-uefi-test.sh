#!/bin/bash
set -euo pipefail

ISO="/home/jachyyeu/osworld-installer/out/altos-2026.06.12-x86_64.iso"
DISK="/home/jachyyeu/osworld-installer/vm-test/target-disk.img"
OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS="/usr/share/edk2/x64/OVMF_VARS.4m.fd"
SERIAL_LOG="/home/jachyyeu/osworld-installer/vm-test/serial.log"

# Copy OVMF vars so we don't corrupt the original
cp "$OVMF_VARS" /home/jachyyeu/osworld-installer/vm-test/ovmf_vars.fd

rm -f "$SERIAL_LOG"

setsid qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -smp 2 \
  -cpu host \
  -cdrom "$ISO" \
  -drive file="$DISK",format=raw,if=virtio \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file=/home/jachyyeu/osworld-installer/vm-test/ovmf_vars.fd \
  -serial file:"$SERIAL_LOG" \
  -display none \
  -vga none \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  > uefi-nohup.out 2>&1 &

QEMU_PID=$!
echo "$QEMU_PID" > qemu.pid
echo "QEMU PID: $QEMU_PID"
