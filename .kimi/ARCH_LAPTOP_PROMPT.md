# For Kimi Code on the Arch Laptop

> **Context for the next Kimi Code session on the Arch laptop.**  
> The user will ask you to connect to their Windows desktop (`jachym-pc`) and continue the AltOS Installer extended end-to-end test.

## Quick summary

- The Windows desktop is at Tailscale IP **`100.103.228.71`** (machine name `jachym-pc`).
- OpenSSH Server is installed and running on port 22.
- User on the desktop is **`JA`**; use the Windows password when SSH prompts.
- PowerShell is the default SSH shell.
- The project repo is cloned to **`D:\osworld-installer`** on the desktop.
- The latest code (including test-mode overrides and docs) has already been pushed to GitHub.

## What the user wants to do tomorrow

Continue the automated pre-reboot test that exercises **real disk partitioning**, **ISO download**, **rEFInd installation**, and **finalize**, stopping just before the actual reboot. See `.kimi/STATUS.md` for full details.

## Step-by-step for you (Kimi) on the Arch laptop

1. **Confirm Tailscale is working on the laptop.**
   ```bash
   sudo systemctl is-active tailscaled
   tailscale status | grep jachym-pc
   ping -c 3 100.103.228.71
   ```

2. **SSH into the desktop.**
   ```bash
   ssh JA@100.103.228.71
   ```

3. **Land in the project directory.**
   ```powershell
   cd D:\osworld-installer
   ```

4. **Pull latest code** (the user may also push changes from the laptop).
   ```powershell
   git pull
   ```

5. **Verify no leftover test artifacts** from a previous run:
   ```powershell
   Get-Volume -FileSystemLabel 'OSWORLDBOOT' -ErrorAction SilentlyContinue
   Test-Path C:\altos-test-state.json
   ```
   If either exists, investigate before continuing.

6. **Rebuild if the user made code changes.** Otherwise the existing release binary already has test mode baked in:
   ```powershell
   cd D:\osworld-installer
   $env:VITE_TEST_MODE='true'
   npm run tauri build
   ```

7. **Run the automated test.**
   ```powershell
   cd D:\osworld-installer
   powershell.exe -ExecutionPolicy Bypass -NoProfile -File "D:\auto-test.ps1"
   ```
   This needs Administrator privileges. The SSH session should already be elevated because `JA` is in the Administrators group.

8. **Wait.** The test takes several minutes because it:
   - Autoplays through all UI screens.
   - Shrinks C: by 3 GB and creates OSWORLDBOOT + Linux partitions.
   - Downloads the Arch Linux ISO (~1 GB).
   - Extracts kernel/initrd and installs rEFInd.
   - Finalizes and stops at `ready_to_reboot`.

9. **Copy results back to the laptop** (run from a local Arch terminal, not inside SSH):
   ```bash
   scp -r JA@100.103.228.71:'D:/test-screenshots' ./test-screenshots
   scp JA@100.103.228.71:'D:/test-results.json' ./test-results.json
   scp JA@100.103.228.71:'D:/test-report.md' ./test-report.md
   ```

10. **Show the user the report and screenshots.** Decide next fixes together.

## Safety reminders to communicate to the user

- The test performs **real disk partitioning** on the desktop.
- The final reboot is intercepted in test mode, but if something unexpected happens, the machine could be left with extra partitions or a modified EFI boot menu.
- Do not reboot the desktop manually while OSWORLDBOOT/rEFInd are present unless they want to test the real boot flow.
- The test script includes a best-effort cleanup function, but if it fails mid-stage, manual cleanup via `diskpart` or the app's uninstaller may be needed.

## If SSH or Tailscale doesn't work

- Check Tailscale admin console for both devices being connected.
- On the desktop, check: `Get-Service sshd` and `Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'`.
- Try `Restart-Service sshd` on the desktop.
- If the desktop is offline, the user must resolve that locally; there's no remote fallback.

## Key files to read on the desktop if you need details

- `D:\osworld-installer\.kimi\STATUS.md` — where the work was paused.
- `D:\osworld-installer\.kimi\REMOTE_SETUP.md` — full remote access instructions.
- `D:\osworld-installer\src-tauri\src\main.rs` — backend logic including test-mode overrides.
- `D:\osworld-installer\src\components\InstallationProgressWindow.tsx` — frontend autoplay logic.
- `D:\auto-test.ps1` — PowerShell test runner and cleanup.
