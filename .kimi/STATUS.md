# AltOS Installer Extended Test — Where We Left Off

**Date:** 2026-06-07  
**Machine:** jachym-pc (Windows desktop, dual-boot Windows/Arch)  
**Goal:** Run the automated end-to-end test all the way through real disk partitioning, ISO download, rEFInd install, and finalize, stopping just before the actual reboot.

## What is already done

1. **Backend test-mode infrastructure**
   - `set_test_mode` Tauri command + `TEST_MODE_ENABLED` AtomicBool in `src-tauri/src/main.rs`.
   - `reboot_to_installer` intercepts the real reboot in test mode and writes `progress:ready_to_reboot` state.
   - `write_install_state` helper writes stage checkpoints to `C:\altos-test-state.json`.

2. **Frontend autoplay extended to installation**
   - `InstallationProgressWindow.tsx` auto-clicks **Start Installation** after 1.2 s in test mode.
   - State writes added for `verify_start`, `verify_complete`, `finalize_start`, `finalize_complete`.

3. **Backend overrides for low-disk-space test runs**
   - In test mode, `prepare_staging` caps `linux_size_gb` to `1` and uses a `1 GB` buffer instead of `10 GB`.
   - The post-shrink "15% free on C:" check is skipped in test mode.
   - This lets the test run on the current C: drive (~4.6 GB free, 96 GB total).

4. **PowerShell test runner (`D:\auto-test.ps1`)**
   - Monitors the full stage sequence from `welcome` through `progress:ready_to_reboot`.
   - Timeout is 1200 s.
   - Includes `Cleanup-TestPartitions` that removes OSWORLDBOOT + companion Linux partition and extends C: before/after the test.

5. **Remote access set up for the Arch laptop tomorrow**
   - Tailscale active on `100.103.228.71` (machine `jachym-pc`).
   - OpenSSH Server installed and running on port 22.
   - Windows Firewall allows SSH on all profiles.
   - PowerShell is the default SSH shell.
   - Instructions live in `.kimi/REMOTE_SETUP.md`.

6. **Build status**
   - Last successful test build: `VITE_TEST_MODE=true npm run tauri build` → `D:\osworld-installer\src-tauri\target\release\osworld-installer.exe`.
   - `cargo check`, `npx tsc --noEmit`, and `npx vitest run` all pass.

## What is NOT done yet

- **The extended end-to-end test has NOT been run.** We were about to run it when we decided to pause for today.
- **No real disk partitioning has happened yet** on this machine, so the code changes above are theoretical until executed.

## How to resume tomorrow from the Arch laptop

1. SSH into the desktop:
   ```bash
   ssh JA@100.103.228.71
   ```
2. Pull the latest code if you pushed changes from the laptop:
   ```powershell
   cd D:\osworld-installer
   git pull
   ```
3. Rebuild with test mode if anything changed:
   ```powershell
   cd D:\osworld-installer
   $env:VITE_TEST_MODE='true'
   npm run tauri build
   ```
   In Git Bash / MSYS2 use:
   ```bash
   VITE_TEST_MODE=true npm run tauri build
   ```
4. Make sure no stale OSWORLDBOOT partitions or state files are left:
   ```powershell
   Get-Volume -FileSystemLabel 'OSWORLDBOOT' -ErrorAction SilentlyContinue
   Test-Path C:\altos-test-state.json
   ```
5. Run the test:
   ```powershell
   cd D:\osworld-installer
   powershell.exe -ExecutionPolicy Bypass -NoProfile -File "D:\auto-test.ps1"
   ```
6. The test will take a while because it performs a real ~1 GB Arch ISO download. Screenshots and reports land in `D:\test-screenshots\`, `D:\test-results.json`, and `D:\test-report.md`.
7. Copy results back to the laptop:
   ```bash
   scp -r JA@100.103.228.71:'D:/test-screenshots' ./test-screenshots
   scp JA@100.103.228.71:'D:/test-results.json' ./test-results.json
   scp JA@100.103.228.71:'D:/test-report.md' ./test-report.md
   ```

## Things to watch out for

- **C: drive free space is tight** (~4.6 GB). The test-mode override shrinks C: by 3 GB (1 GB Linux + 2 GB OSWORLDBOOT) and downloads a ~1 GB ISO onto the 2 GB FAT32 boot partition. If the ISO is unusually large one day, the download/extraction may fail.
- **Network speed** determines how long the test spends in `download_start` → `download_complete`.
- **Cleanup is best-effort in PowerShell.** If something goes wrong mid-test and partitions are left behind, you can clean them up from the uninstaller UI or manually via `diskpart`/`Get-Partition`.
- **Do not reboot the desktop while OSWORLDBOOT/rEFInd are present** unless you want to test the real boot path; that will actually change the boot menu.

## Next steps after the test passes

1. Review `D:\test-report.md` and screenshots.
2. Fix any failures.
3. Re-run until `progress:ready_to_reboot` is reached and all stages PASS.
4. Commit and push the final code.
