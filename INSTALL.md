# Installation Guide — AltOS

## Requirements

- Windows 10 or 11 (64-bit, UEFI mode)
- At least 30 GB of free disk space
- Internet connection
- Administrator privileges

## Quick Start

1. **Download** the latest `AltOS-Installer.exe` and `altos-x86_64.iso` from the [Releases](https://github.com/jachyyeu/osworld-installer/releases) page.

2. **Run the installer** on Windows. It will:
   - Check system compatibility
   - Stage the ISO and config onto a spare partition
   - Install the rEFInd bootloader
   - Reboot into the AltOS installer

3. **Let the installer run.** The custom Arch ISO will boot automatically and install AltOS without any interaction.

4. **First-boot wizard.** After installation completes and the system reboots, a wizard will help you:
   - Import files from Windows (if dual-booting)
   - Pick a desktop theme
   - Install recommended apps

## Dual-Boot vs Wipe

| Mode | Description |
|------|-------------|
| **Dual-Boot** | Shrinks your Windows partition and installs AltOS alongside it. You can choose which OS to boot at startup. |
| **Wipe** | Erases the entire selected disk and installs AltOS only. **All Windows data will be lost.** |

## Manual ISO Boot (Advanced)

If the automatic reboot fails, you can manually boot the ISO:

1. Copy `altos-x86_64.iso` to a USB drive using Rufus or `dd`.
2. Boot from the USB drive.
3. The installer will auto-start if an `OSWORLDBOOT` partition exists.
4. If not, it will drop to a shell so you can debug.

## After Installation

- Default username and password are set during the Windows installer flow.
- NetworkManager handles Wi-Fi and Ethernet.
- KDE Plasma is the default desktop environment.
- The first-boot wizard runs once on initial login.
