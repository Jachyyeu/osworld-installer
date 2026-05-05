#Requires -RunAsAdministrator
# ============================================================
# windows-uninstall.ps1 — Windows-side AltOS uninstaller
# Run this from Windows if you can still boot into Windows.
# ============================================================

$ErrorActionPreference = "Stop"
$LogFile = "$env:TEMP\altos-uninstall.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Show-Banner {
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Red
    Write-Host "  ALTOS WINDOWS UNINSTALLER" -ForegroundColor Red
    Write-Host "=======================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "This will remove AltOS partitions and restore Windows Boot Manager." -ForegroundColor Yellow
    Write-Host "Your Windows files will NOT be deleted." -ForegroundColor Yellow
    Write-Host ""
}

# --- Main ---------------------------------------------------
Show-Banner

$confirm = Read-Host "Type REMOVE to confirm uninstall, or anything else to abort"
if ($confirm -ne "REMOVE") {
    Write-Log "Uninstall cancelled by user."
    exit 0
}

Write-Log "Starting AltOS uninstall from Windows..."

# Find OSWORLDBOOT partition
$osworldPart = Get-Partition | Where-Object { $_.Type -eq "Basic" -and (Get-Volume -Partition $_).FileSystemLabel -eq "OSWORLDBOOT" } | Select-Object -First 1

# Find Linux partitions (no drive letter, raw or btrfs)
$linuxParts = Get-Partition | Where-Object {
    $vol = Get-Volume -Partition $_ -ErrorAction SilentlyContinue
    return ($vol.FileSystem -eq "BTRFS" -or ($_.Type -eq "Basic" -and -not $vol.DriveLetter))
} | Where-Object {
    $vol = Get-Volume -Partition $_ -ErrorAction SilentlyContinue
    $vol.FileSystemLabel -notmatch "Windows|Recovery|EFI"
}

# Find ESP
$esp = Get-Partition | Where-Object { $_.Type -eq "System" } | Select-Object -First 1

# Remove OSWORLDBOOT
if ($osworldPart) {
    Write-Log "Removing OSWORLDBOOT partition (Disk $($osworldPart.DiskNumber), Part $($osworldPart.PartitionNumber))..."
    Remove-Partition -DiskNumber $osworldPart.DiskNumber -PartitionNumber $osworldPart.PartitionNumber -Confirm:$false
    Write-Log "OSWORLDBOOT removed."
} else {
    Write-Log "OSWORLDBOOT partition not found."
}

# Remove Linux partitions
foreach ($part in $linuxParts) {
    try {
        Write-Log "Removing Linux partition (Disk $($part.DiskNumber), Part $($part.PartitionNumber))..."
        Remove-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -Confirm:$false
        Write-Log "Linux partition removed."
    } catch {
        Write-Log "WARNING: Could not remove partition: $_"
    }
}

# Remove GRUB/rEFInd from ESP
if ($esp) {
    $avail = 83..90 | ForEach-Object { [char]$_ } | Where-Object { -not (Test-Path "$($_):") } | Select-Object -First 1
    if ($avail) {
        Add-PartitionAccessPath -DiskNumber $esp.DiskNumber -PartitionNumber $esp.PartitionNumber -AccessPath "$($avail):"
        Start-Sleep -Seconds 1

        $refindPath = "$($avail):\EFI\refind"
        $grubPath   = "$($avail):\EFI\grub"

        if (Test-Path $refindPath) {
            Remove-Item -Recurse -Force $refindPath
            Write-Log "Removed rEFInd from EFI."
        }
        if (Test-Path $grubPath) {
            Remove-Item -Recurse -Force $grubPath
            Write-Log "Removed GRUB from EFI."
        }

        Remove-PartitionAccessPath -DiskNumber $esp.DiskNumber -PartitionNumber $esp.PartitionNumber -AccessPath "$($avail):"
    } else {
        Write-Log "WARNING: No available drive letter to mount ESP. Manual cleanup may be needed."
    }
}

# Restore Windows Boot Manager via bcdedit
Write-Log "Restoring Windows Boot Manager..."
$entries = bcdedit /enum firmware | Select-String -Pattern "identifier" | ForEach-Object { ($_ -split "\s+")[1] }
$winEntry = $entries | Where-Object { $_ -match "{bootmgr}" } | Select-Object -First 1

if ($winEntry) {
    bcdedit /set "$winEntry" path "\EFI\Microsoft\Boot\bootmgfw.efi" | Out-Null
    bcdedit /displayorder "$winEntry" /addfirst | Out-Null
    Write-Log "Windows Boot Manager restored as default."
} else {
    Write-Log "WARNING: Could not find Windows Boot Manager entry in BCD."
}

# Remove any OSWorld Installer BCD entries
$osworldEntries = bcdedit /enum | Select-String -Pattern "OSWorld Installer" -Context 1
if ($osworldEntries) {
    foreach ($match in $osworldEntries) {
        $guid = ($match.Context.PreContext[0] -split "\s+")[1]
        if ($guid -match "\{.*\}") {
            bcdedit /delete $guid /cleanup | Out-Null
            Write-Log "Removed OSWorld Installer BCD entry: $guid"
        }
    }
}

# Optional: expand Windows partition
$expand = Read-Host "Expand Windows C: drive to fill freed space? [y/N]"
if ($expand -eq "y" -or $expand -eq "Y") {
    $cVol = Get-Volume -DriveLetter C
    $cPart = Get-Partition | Where-Object { $_.AccessPaths -contains "C:\\" }
    if ($cPart) {
        $maxSize = (Get-PartitionSupportedSize -DiskNumber $cPart.DiskNumber -PartitionNumber $cPart.PartitionNumber).SizeMax
        Resize-Partition -DiskNumber $cPart.DiskNumber -PartitionNumber $cPart.PartitionNumber -Size $maxSize
        Write-Log "Windows partition expanded."
    }
}

# Finish
Write-Log ""
Write-Log "======================================="
Write-Log "  Uninstall complete"
Write-Log "======================================="
Write-Log "Log saved to: $LogFile"
Write-Log "Reboot your computer to finish."

# Rescue USB instructions
Write-Log ""
Write-Log "If Windows does not boot after restart:"
Write-Log "1. Create a Windows Recovery USB on another PC."
Write-Log "2. Boot from the USB and select 'Repair your computer'."
Write-Log "3. Run: bootrec /fixmbr && bootrec /fixboot && bootrec /rebuildbcd"
