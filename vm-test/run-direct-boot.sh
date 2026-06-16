#!/bin/bash
set -euo pipefail

ISO="/home/jachyyeu/osworld-installer/out/altos-2026.06.12-x86_64.iso"
KERNEL="/tmp/iso-check/arch/boot/x86_64/vmlinuz-linux"
INITRD="/tmp/iso-check/arch/boot/x86_64/initramfs-linux.img"

rm -f vm-test-run.log qemu-monitor.sock qemu.pid qemu-nohup.out

setsid qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -smp 2 \
  -cpu host \
  -cdrom "$ISO" \
  -kernel "$KERNEL" \
  -initrd "$INITRD" \
  -append "archisobasedir=arch archisolabel=ALTOS_202606 console=ttyS0,115200" \
  -drive file=target-disk.img,format=raw,if=virtio \
  -serial file:vm-test-run.log \
  -display none \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -chardev socket,id=mon0,path=qemu-monitor.sock,server=on,wait=off \
  -mon chardev=mon0,mode=control \
  > qemu-nohup.out 2>&1 &

QEMU_PID=$!
echo "$QEMU_PID" > qemu.pid
echo "QEMU PID: $QEMU_PID"
