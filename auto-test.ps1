#Requires -RunAsAdministrator
# Auto-test AltOS Installer pre-reboot flow using autoplay mode.
# The app (built with VITE_TEST_MODE=true) drives itself through each screen.
# This script only launches the app, watches the state file, takes screenshots, and validates.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ExePath = 'D:\osworld-installer\src-tauri\target\release\osworld-installer.exe'
$StatePath = 'C:\altos-test-state.json'
$OutputDir = 'D:\test-screenshots'
$ResultsPath = 'D:\test-results.json'
$ReportPath = 'D:\test-report.md'

$global:process = $null

function Ensure-Dir {
    param([string]$Path)
    if (!(Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Save-Screenshot {
    param([string]$Path)
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $g.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

function Read-StateFile {
    if (!(Test-Path $StatePath)) { return @() }
    try {
        $txt = Get-Content $StatePath -Raw -ErrorAction Stop
        $arr = $txt | ConvertFrom-Json -ErrorAction Stop
        if ($arr -is [array]) { return $arr }
        return @($arr)
    } catch { return @() }
}

function Wait-ForWindow {
    param([int]$TimeoutSec = 30)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $p = Get-Process | Where-Object { $_.ProcessName -eq 'osworld-installer' } | Select-Object -First 1
        if ($p -and $p.MainWindowHandle -ne 0) { return $p }
        Start-Sleep -Milliseconds 500
    }
    throw 'Installer window not found'
}

function Stop-Installer {
    if ($global:process -and !$global:process.HasExited) {
        try { $global:process.Kill() } catch {}
    }
    // Intentionally removed: global process kill can race with concurrent test runs
    Start-Sleep -Seconds 1
}

function Cleanup-TestPartitions {
    # Best-effort cleanup of OSWORLDBOOT and its companion Linux partition,
    # mirroring the Rust cleanup_staging logic. Silently continues on errors.
    try {
        $osworld = Get-Volume -FileSystemLabel 'OSWORLDBOOT' -ErrorAction SilentlyContinue
        if (-not $osworld) { return }

        $diskNumber = (Get-Partition -DriveLetter D).DiskNumber
        $osworldLetter = $osworld.DriveLetter
        $osworldPart = (Get-Partition | Where-Object { $_.DriveLetter -eq $osworldLetter }).PartitionNumber

        # Linux partition is expected to be the last partition on the system disk.
        $linuxPart = (Get-Partition -DiskNumber $diskNumber | Sort-Object PartitionNumber -Descending | Select-Object -First 1).PartitionNumber

        if ($linuxPart -and ($linuxPart -ne $osworldPart)) {
            $script = "select disk $diskNumber`nselect partition $linuxPart`ndelete partition override`n"
            $script | diskpart | Out-Null
        }
        if ($osworldPart) {
            $script = "select disk $diskNumber`nselect partition $osworldPart`ndelete partition override`n"
            $script | diskpart | Out-Null
        }
        $script = "select disk $diskNumber`nselect volume D`nextend`n"
        $script | diskpart | Out-Null

        Write-Host 'Cleaned up test partitions.'
    } catch {
        Write-Host "Cleanup warning: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Ensure-Dir $OutputDir
Stop-Installer
Cleanup-TestPartitions
if (Test-Path $StatePath) { Remove-Item $StatePath -Force }
Get-ChildItem $OutputDir -Filter '*.png' -ErrorAction SilentlyContinue | Remove-Item -Force

$results = [ordered]@{
    overall = 'FAIL'
    steps = @()
    error = $null
}

function Add-Step($Name, $Status, $Expected, $Actual, $Screenshot) {
    $results.steps += [PSCustomObject]@{
        name = $Name
        status = $Status
        expected = $Expected
        actual = $Actual
        screenshot = $Screenshot
    }
}

# Expected sequence of states. For progress screen we track stage substates.
$expectedSequence = @(
    @{ key = 'welcome';            name = 'Welcome' }
    @{ key = 'systemcheck';        name = 'System Check' }
    @{ key = 'disk';               name = 'Disk Selection' }
    @{ key = 'usersetup';          name = 'User Setup' }
    @{ key = 'edition';            name = 'Edition' }
    @{ key = 'progress:preparing'; name = 'Pre-Install' }
    @{ key = 'progress:prepare_start';    name = 'Install: Prepare Start' }
    @{ key = 'progress:prepare_partitioned'; name = 'Install: Partitioned' }
    @{ key = 'progress:prepare_complete';  name = 'Install: Prepare Complete' }
    @{ key = 'progress:download_start';    name = 'Install: Download Start' }
    @{ key = 'progress:download_complete'; name = 'Install: Download Complete' }
    @{ key = 'progress:verify_start';      name = 'Install: Verify Start' }
    @{ key = 'progress:verify_complete';   name = 'Install: Verify Complete' }
    @{ key = 'progress:bootloader_start';  name = 'Install: Bootloader Start' }
    @{ key = 'progress:bootloader_complete'; name = 'Install: Bootloader Complete' }
    @{ key = 'progress:finalize_start';    name = 'Install: Finalize Start' }
    @{ key = 'progress:finalize_complete'; name = 'Install: Finalize Complete' }
    @{ key = 'progress:ready_to_reboot';   name = 'Install: Ready to Reboot' }
)

function Get-StateKey($state) {
    if ($state.screen -eq 'progress' -and $state.stage) {
        return "progress:$($state.stage)"
    }
    return $state.screen
}

try {
    Write-Host 'Launching installer in autoplay mode...'
    $si = New-Object System.Diagnostics.ProcessStartInfo
    $si.FileName = $ExePath
    $si.WorkingDirectory = Split-Path $ExePath
    $si.UseShellExecute = $true
    $global:process = [System.Diagnostics.Process]::Start($si)

    $proc = Wait-ForWindow -TimeoutSec 30
    Write-Host "Window found (PID $($proc.Id)). Starting autoplay monitor..."

    $seen = @()
    $stepIndex = 0
    $lastState = $null
    $start = [System.Diagnostics.Stopwatch]::StartNew()

    while ($start.Elapsed.TotalSeconds -lt 1200) {
        $states = Read-StateFile
        if ($states.Count -gt 0 -and ($null -eq $lastState -or ($states | ConvertTo-Json -Compress) -ne ($lastState | ConvertTo-Json -Compress))) {
            $lastState = $states
            foreach ($state in $states) {
                $key = Get-StateKey $state
                if ($key -and $key -notin $seen -and $key -notmatch '^app_') {
                    $seen += $key
                    $safeKey = $key -replace ':', '-'
                    $shot = "$OutputDir\$($stepIndex.ToString('00'))-$safeKey.png"
                    Save-Screenshot $shot
                    Write-Host "Reached state: $key -> $shot"

                    $exp = $expectedSequence[$stepIndex]
                    if ($key -eq $exp.key) {
                        Add-Step -Name $exp.name -Status 'PASS' -Expected @{ state = $exp.key } -Actual $state -Screenshot $shot
                        Write-Host "  $($exp.name) PASS"
                    } else {
                        Add-Step -Name "Expected $($exp.key), got $key" -Status 'FAIL' -Expected @{ state = $exp.key } -Actual $state -Screenshot $shot
                        throw "Unexpected state at step $stepIndex`: $key"
                    }
                    $stepIndex++

                    if ($key -eq 'progress:ready_to_reboot') {
                        Write-Host 'Reached ready-to-reboot state. Stopping before actual reboot.'
                        break
                    }
                }
            }
            if ($key -eq 'progress:ready_to_reboot') { break }
        }
        Start-Sleep -Milliseconds 100
    }

    # Always capture final screenshot for debugging
    $finalShot = "$OutputDir\99-final.png"
    Save-Screenshot $finalShot

    if ($stepIndex -lt $expectedSequence.Count) {
        for ($i = $stepIndex; $i -lt $expectedSequence.Count; $i++) {
            $exp = $expectedSequence[$i]
            Add-Step -Name $exp.name -Status 'FAIL' -Expected @{ state = $exp.key } -Actual @{ error = 'Timed out waiting for state' } -Screenshot $finalShot
        }
        throw 'Timed out waiting for all states'
    }

    $results.overall = 'PASS'
} catch {
    $results.error = $_.Exception.Message
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Stop-Installer
    Cleanup-TestPartitions
}

$results | ConvertTo-Json -Depth 10 | Set-Content $ResultsPath

$report = @()
$report += '# AltOS Installer Pre-Reboot Test Report'
$report += ''
$report += "**Overall:** $($results.overall)"
if ($results.error) {
    $report += ''
    $report += "**Error:** $($results.error)"
}
$report += ''
$report += '## Steps'
$report += '| Step | Status | Screenshot |'
$report += '|------|--------|------------|'
foreach ($step in $results.steps) {
    $link = if ($step.screenshot) { "[$($step.screenshot)]($($step.screenshot))" } else { '-' }
    $report += "| $($step.name) | $($step.status) | $link |"
}
$report += ''
$report += '## Last State'
$report += ''
$report += '```json'
$report += $lastState | ConvertTo-Json -Depth 10
$report += '```'
$report | Set-Content $ReportPath

Write-Host "Results saved to: $ResultsPath"
Write-Host "Report saved to: $ReportPath"
Write-Host "Overall: $($results.overall)"
