# Remote Testing Setup — Arch Laptop → Windows Desktop

This document explains how to run the AltOS Installer automated test on the Windows desktop (`jachym-pc`) from the Arch Linux laptop over a different WiFi.

## What is already set up on the Windows desktop

1. **Tailscale** is installed and logged in as `jachym-pc`.
   - Tailscale IP: `100.103.228.71`
   - Machine name: `jachym-pc`
2. **OpenSSH Server** is installed and running on port 22.
3. **Windows Firewall** allows SSH on Domain/Private/Public profiles.
4. **PowerShell** is the default SSH shell.

## What you need to set up on the Arch laptop

### 1. Install Tailscale

```bash
sudo pacman -S tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
```

Authenticate in the browser link that appears. Make sure you log in to the **same Tailscale account** as the Windows desktop.

Verify you can reach the desktop:

```bash
ping 100.103.228.71
```

### 2. Install SSH client

Usually already installed. If not:

```bash
sudo pacman -S openssh
```

### 3. SSH into the Windows desktop

```bash
ssh JA@100.103.228.71
```

Use the Windows password for user `JA` when prompted.

> If you want passwordless login, generate a key on the laptop and add it to the desktop's `~/.ssh/authorized_keys` (Windows path: `C:\Users\JA\.ssh\authorized_keys`).

### 4. Run the automated test remotely

Once SSH'd in, the test can be started with:

```powershell
cd D:\osworld-installer
# Optional: pull latest changes if you pushed from the laptop
git pull

# Run the test (requires Administrator; the desktop session is already Admin)
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "D:\auto-test.ps1"
```

The test will:
1. Build the app with `VITE_TEST_MODE=true` if needed (or use the existing release binary).
2. Launch the installer.
3. Autopilot through Welcome → System Check → Disk Selection → User Setup → Edition.
4. Click **Start Installation** and run through the real prepare/download/verify/bootloader/finalize stages.
5. Stop at the **Ready to Reboot** state (the backend intercepts the actual reboot command in test mode).
6. Save screenshots and a JSON/Markdown report to `D:\test-screenshots\`, `D:\test-results.json`, and `D:\test-report.md`.

### 5. Retrieve results to the laptop

From the Arch laptop (not inside SSH), run:

```bash
scp -r JA@100.103.228.71:'D:/test-screenshots' ./test-screenshots
scp JA@100.103.228.71:'D:/test-results.json' ./test-results.json
scp JA@100.103.228.71:'D:/test-report.md' ./test-report.md
```

## Running Kimi Code remotely over SSH

If you want to use Kimi Code CLI on the desktop from the laptop, you have two options:

### Option A: Run Kimi Code directly over SSH

```bash
ssh JA@100.103.228.71
# Inside the SSH session:
cd D:\osworld-installer
kimi
```

This gives you a Kimi Code session on the desktop through your laptop's terminal.

### Option B: VS Code Remote SSH

1. On the laptop, install VS Code and the **Remote - SSH** extension.
2. Connect to `JA@100.103.228.71`.
3. Open `D:\osworld-installer`.
4. Use Kimi Code inside VS Code as usual.

## Important safety notes

- The extended test performs **real disk partitioning** on the desktop (shrinks C:, creates OSWORLDBOOT and Linux partitions), downloads an ISO, and installs rEFInd.
- In test mode, the **final reboot command is intercepted** and will not reboot the machine.
- If any stage fails, the app's existing rollback logic attempts to clean up partitions.
- Do **not** run this test while you are actively using the desktop for important work, and ensure you have backups.

## Troubleshooting

### Tailscale connection fails
- Make sure both devices show as `Connected` in the Tailscale admin console.
- Try `tailscale ping jachym-pc` from the laptop.

### SSH connection fails
- On the desktop, verify the SSH service: `Get-Service sshd`
- Verify the firewall rule: `Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'`
- Try restarting SSH: `Restart-Service sshd`

### Test script says "not running as Administrator"
- The SSH session must be launched by an Administrator user. User `JA` on the desktop is in the Administrators group.
- If needed, open an elevated PowerShell locally on the desktop and restart the SSH service from there.

### Want to clean up after a test run
- If the test completed successfully, the desktop will have an `OSWORLDBOOT` partition and a Linux partition.
- To remove them, run the AltOS Installer normally, go to **Remove AltOS**, and follow the prompts.
- Or use the uninstaller Tauri commands manually from an elevated PowerShell:
  ```powershell
  cd D:\osworld-installer\src-tauri
  cargo run -- remove_altos_partitions "OSWORLD" $true
  ```
