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
| `lib/drivers.sh` | **(NEW)** Auto-detect GPU/WiFi and install correct drivers |
| `lib/system.sh` | Timezone, locale, hostname, user, sudo, NetworkManager |
| `lib/migration.sh` | **(NEW)** Migrate Documents, Pictures, bookmarks, WiFi from Windows |
| `lib/bootloader.sh` | Install GRUB with Windows detection (`os-prober`) |
| `lib/logging.sh` | **(NEW)** Universal logging to both Live env and target system |
| `lib/compatibility.sh` | **(NEW)** Hardware compatibility check before partitioning |
| `example-config.json` | Example input for testing |

## Execution Order

`install.sh` runs the following steps in order:

1. **`verify_environment`** — Check root, UEFI, internet
2. **`verify_compatibility`** — Detect GPU, WiFi, storage, audio. Blocks on eMMC.
3. **`prepare_disk`** — Partition the target disk (wipe or shrink Windows)
4. **`install_base`** — Format, mount, `pacstrap` Arch base system
5. **`install_drivers`** — Detect and install GPU + WiFi drivers, regenerate initramfs
6. **`configure_system`** — Timezone, locale, hostname, user, sudo, NetworkManager
7. **`migrate_windows_files`** — (dual-boot only) Copy user files, bookmarks, WiFi profiles
8. **`install_bootloader`** — GRUB + os-prober for Windows detection
9. **`finalize`** — Unmount, sync, copy log to user home

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

## New Modules

### `lib/logging.sh`

Provides universal logging for the entire installation:

- `log_start()` — Creates `/tmp/altos-install.log` and `/mnt/install.log`
- `log_cmd()` — Wraps any command: logs it, runs it, captures stdout+stderr, logs result
- `log_info()` / `log_warn()` / `log_error()` / `log_ok()` — Colored terminal + file output
- On any failure, the log is automatically copied to `/tmp/altos-crash-report.txt`

All logs go to **both** the Live environment (`/tmp/altos-install.log`) and the target system (`/mnt/install.log`, once `/mnt` is mounted).

### `lib/compatibility.sh`

Runs **before** partitioning to detect hardware issues early:

- **GPU:** Intel (safe), AMD (safe), NVIDIA (warning — proprietary drivers will be installed), Optimus (warning)
- **WiFi:** Intel (safe), Broadcom (warning — may need manual firmware), Realtek (info)
- **Storage:** NVMe/SATA (safe), **eMMC (BLOCKS INSTALL)**
- **Audio:** Intel HDA (safe), other (info)

Output uses color coding: Green = OK, Yellow = warning but continue, Red = block and exit.

### `lib/drivers.sh`

Auto-detects hardware and installs the correct drivers **inside the chroot**:

| Hardware | Packages Installed |
|----------|-------------------|
| NVIDIA GPU | `nvidia-dkms`, `nvidia-utils`, `lib32-nvidia-utils` |
| AMD GPU | `mesa`, `lib32-mesa`, `vulkan-radeon` |
| Intel GPU | `mesa`, `lib32-mesa`, `vulkan-intel` |
| Broadcom WiFi | `broadcom-wl-dkms` |
| Realtek WiFi | `rtl8821ce-dkms`, `rtl88x2bu-dkms`, etc. (chip-specific) |

Also sets `nvidia-drm.modeset=1` in GRUB and regenerates the initramfs.

### `lib/migration.sh`

Migrates files from the existing Windows installation **only in dual-boot mode**:

- Mounts the Windows NTFS partition read-only
- Copies user folders: Documents, Pictures, Desktop, Downloads, Music, Videos
- Copies Firefox and Chrome/Edge bookmarks
- Copies Windows WiFi profiles (passwords must be re-entered)
- Creates a `README.txt` in `~/windows-migration/`
- Fixes ownership of all copied files to the new Linux user

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
- `lib/compatibility.sh` blocks installation on unsupported hardware (eMMC).
- On any failure, `/tmp/altos-crash-report.txt` contains the full log.
