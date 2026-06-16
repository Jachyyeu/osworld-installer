# AltOS Dual-Boot Install Status

**Saved:** 2026-06-14
**State:** Paused — user taking a break before forcing one-time boot into AltOS installer.

## What We Did

1. Rebuilt custom AltOS ISO (`out/altos-2026.06.14-x86_64.iso`) with:
   - OpenSSH + Tailscale pre-installed and enabled
   - Dual-boot installer now shrinks the **largest** NTFS partition (D:) instead of the first one
   - Kernel cmdline UEFI bypass `altos_skip_uefi_check` for VM testing
   - GRUB serial console for headless VM verification

2. VM end-to-end test passed.

3. Staged the install on Windows test PC `jachym-pc` (Tailscale IP `100.103.228.71`):
   - Created ~5 GB FAT32 `OSWORLDBOOT` partition on Disk 1 (Samsung 500 GB NVMe)
   - Copied custom ISO contents + `arch.iso` loop image to `OSWORLDBOOT`
   - Installed rEFInd to the Windows ESP
   - Created a rEFInd firmware boot entry: `{f5d0ebf2-47c0-11f0-b0c6-001a7dda7115}`
   - Rebooted

4. On reboot, rEFInd loaded but auto-selected the **existing Arch Linux** install instead of `OSWORLDBOOT`.

## Current Problem

The target PC already had an Arch Linux install that boots by default. We have not yet booted the AltOS installer from `OSWORLDBOOT`.

## Next Step (when resuming)

From inside the existing Arch Linux, force a one-time boot into `OSWORLDBOOT`:

```bash
# Find the OSWORLDBOOT partition
lsblk -f

# Create a temporary EFI boot entry (replace /dev/nvme0n1 and -p 5 with actual disk/partition)
sudo efibootmgr -c -d /dev/nvme0n1 -p 5 -L "AltOS Installer" -l '\EFI\BOOT\BOOTx64.EFI'

# Note the new 4-digit boot number, e.g. Boot0005, then set it as next boot
sudo efibootmgr -n 0005
sudo reboot
```

## Important Notes

- Windows Disk 1 has C: (full), D: (data, ~370 GB free) — installer will shrink D:.
- Existing Arch install will **not** be touched unless its partitions conflict with the new space taken from D:.
- After AltOS installs and reboots, someone must run `tailscale login` on the target PC before remote SSH via Tailscale works.
- Tailscale target IP: `100.103.228.71`
- Windows SSH user/pass: `JA` / `Klokan2009`

## Open Questions

- Does the user want to keep the existing Arch install, or replace it with AltOS?
- What is the exact `OSWORLDBOOT` device path/partition number? (Use `lsblk -f` to confirm.)
