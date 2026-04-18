# Installer Scripts

> **Important:** These scripts run **inside an Arch Linux Live ISO**, not on Windows.
> Boot your PC from the Arch Live USB, then run these scripts to install Linux.

## How it works

1. **Tauri GUI (Windows side)** collects your preferences:
   - Disk to use
   - Installation mode (wipe or dual-boot with Windows)
   - User name, password, timezone, etc.

2. The GUI writes a JSON file to `/tmp/install-config.json`.

3. **These bash scripts** read that JSON and perform the actual installation.

## Files

| File | Purpose |
|------|---------|
| `install.sh` | Main orchestrator. Run this. |
| `lib/disk.sh` | Partitioning (shrink Windows, create EFI/root/home) |
| `lib/bootstrap.sh` | Format partitions, mount, `pacstrap` base system |
| `lib/bootloader.sh` | Install GRUB with Windows detection (`os-prober`) |
| `lib/system.sh` | Timezone, locale, hostname, user, sudo, NetworkManager |
| `example-config.json` | Example input for testing |

## Usage

```bash
# Show what would happen without changing anything (default)
sudo bash scripts/installer/install.sh --dry-run

# Actually install
sudo bash scripts/installer/install.sh --confirm
```

## Safety

- `--dry-run` prints every step but touches **nothing**.
- `--confirm` is required to make real changes.
- The script refuses to run if the target disk is mounted (protects the Live USB).
- `set -euo pipefail` ensures any error stops the script immediately.
