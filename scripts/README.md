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
| `live-bridge.sh` | Auto-finds staged config from OSWORLDBOOT partition and runs `install.sh` |
| `lib/disk.sh` | Partitioning (shrink Windows, create EFI/root/home) |
| `lib/bootstrap.sh` | Format partitions, mount, `pacstrap` base system |
| `lib/bootloader.sh` | Install GRUB with Windows detection (`os-prober`) |
| `lib/system.sh` | Timezone, locale, hostname, user, sudo, NetworkManager |
| `example-config.json` | Example input for testing |

## Boot Staging Flow (Windows → Arch Live ISO)

This is the full handoff from the Windows app to the Linux installer:

1. **Windows app** stages the installation:
   - Shrinks the C: drive
   - Creates a 2 GB FAT32 partition labeled **OSWORLDBOOT**
   - Creates a second raw partition for Linux
   - Downloads the Arch Linux ISO to `OSWORLDBOOT:\arch.iso`
   - Writes `install-config.json` to the `OSWORLDBOOT` partition
   - Installs **rEFInd** bootloader to the EFI System Partition
   - Adds a menu entry that boots the Arch ISO from `OSWORLDBOOT`

2. **User reboots** and selects *"OSWorld Installer"* from the rEFInd menu.

3. **Arch Live ISO boots** (loaded from the staged ISO on `OSWORLDBOOT`).

4. **Inside the Live ISO**, run:
   ```bash
   sudo bash /path/to/live-bridge.sh --confirm
   ```

5. **`live-bridge.sh`** does the bridge work:
   - Mounts the `OSWORLDBOOT` partition
   - Copies `install-config.json` to `/tmp/install-config.json`
   - Validates the JSON
   - Unmounts the partition
   - Hands off to `install.sh` with the same arguments (`--dry-run` or `--confirm`)

6. **`install.sh`** reads the config and installs Arch Linux.

## Usage

### Manual run (with mock config)
```bash
# Show what would happen without changing anything (default)
sudo bash scripts/installer/install.sh --dry-run

# Actually install
sudo bash scripts/installer/install.sh --confirm
```

### Automatic bridge (from staged Windows setup)
```bash
# Inside Arch Live ISO — auto-detect staged config and install
sudo bash scripts/installer/live-bridge.sh --confirm
```

## Safety

- `--dry-run` prints every step but touches **nothing**.
- `--confirm` is required to make real changes.
- `live-bridge.sh` refuses to run if the `OSWORLDBOOT` partition or config is missing.
- The script refuses to run if the target disk is mounted (protects the Live USB).
- `set -euo pipefail` ensures any error stops the script immediately.
