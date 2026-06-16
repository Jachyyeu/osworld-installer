# Troubleshooting — AltOS Installer

## Windows Installer

### "Could not find any partition labeled OSWORLDBOOT"
The Windows staging step failed. Make sure:
- The installer completed the "Prepare Disk" step without errors.
- You rebooted through the installer (not manually).

### BitLocker Error
BitLocker must be suspended before installation.

**PowerShell (Admin):**
```powershell
Suspend-BitLocker -MountPoint "C:" -RebootCount 0
```

Then restart the installer.

### ISO Download Hangs or Fails
The installer will automatically fall back to the Arch Linux mirror if the custom ISO URL is unreachable. If both fail:
- Check your internet connection.
- Disable VPN or proxy temporarily.
- Manually download the ISO and place it as `D:\arch.iso` on the staging drive, then re-run the installer.

### rEFInd Not Showing After Reboot
- Enter your BIOS/UEFI settings and ensure **Secure Boot** is disabled.
- Check that the EFI partition was created correctly.
- Re-run the installer or manually install rEFInd from a recovery USB.

## Arch Live ISO / Installation

### "Could not find any partition labeled OSWORLDBOOT"
The Windows staging did not complete. Boot back into Windows and run the installer again.

### Installer Stops at "Internet connection not detected"
- The live environment uses `systemd-networkd`. Ethernet should work automatically.
- For Wi-Fi, switch to another TTY (`Ctrl+Alt+F2`), log in as root, and use `iwctl` to connect:
  ```bash
  iwctl station wlan0 connect "Your_SSID"
  ```
- Then switch back to TTY1 (`Ctrl+Alt+F1`) to see the installer resume.

### Pacstrap Fails with Package Errors
- Some packages in `packages/basic.yaml` might not be available in the Arch repos.
- The installer logs skipped packages but continues. Check `/home/<user>/install.log` after reboot.

### Target Disk is the Live USB
The installer detects if the selected disk is mounted (i.e., the Live USB itself) and aborts. Make sure you selected the correct internal disk.

## First Boot

### First-Boot Wizard Does Not Appear
- The wizard is triggered by a KDE autostart desktop file and a systemd fallback service.
- Check if `~/.config/altos/first-boot-done` exists. If so, the wizard already ran.
- To re-run it: `rm ~/.config/altos/first-boot-done` and log out/in.

### PyQt6 Wizard Fails, Terminal Fallback Works
`python-pyqt6` might not have been installed correctly. Install it manually:
```bash
sudo pacman -S python-pyqt6
```

### No Wi-Fi After Reboot
```bash
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth
```

## Recovery

### Boot Failure (3+ failed boots)
The boot monitor will automatically trigger recovery mode. You can also boot the AltOS USB and choose "Rescue Mode" from the rEFInd menu.

### Reinstall Bootloader
Boot the AltOS USB, switch to a TTY, and run:
```bash
sudo bash /usr/share/altos/recovery/reinstall-bootloader.sh
```
