// OSWorld Installer - Tauri v2 Application
// Main Rust backend with system detection and installation logic

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use tauri::{State, Emitter, AppHandle};
use thiserror::Error;
#[cfg(windows)]
use std::ffi::c_void;
// Configuration struct that can be serialized to JSON for the next stage
#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct InstallConfig {
    pub install_type: Option<InstallType>,
    pub windows_version: Option<String>,
    pub disk_free_space_gb: Option<u64>,
    pub ram_gb: Option<u64>,
    pub cpu_info: Option<String>,
    pub secure_boot_enabled: Option<bool>,
    pub bitlocker_enabled: Option<bool>,
    pub selected_disk: Option<String>,
    pub linux_size_gb: Option<u64>,
    pub username: Option<String>,
    pub computer_name: Option<String>,
    pub password: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq)]
pub enum InstallType {
    DualBoot,
    ReplaceWindows,
}

// Custom error types for proper error handling
#[derive(Error, Debug, Serialize)]
pub enum InstallerError {
    #[error("System check failed: {0}")]
    SystemCheckFailed(String),
    #[error("Validation error: {0}")]
    ValidationError(String),
    #[error("Installation error: {0}")]
    InstallationError(String),
    #[error("Unknown error: {0}")]
    Unknown(String),
}

pub type Result<T> = std::result::Result<T, InstallerError>;

// Application state to store configuration across windows
pub struct AppState {
    config: Mutex<InstallConfig>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            config: Mutex::new(InstallConfig::default()),
        }
    }
}

// System information structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SystemInfo {
    pub windows_version: String,
    pub disk_free_space_gb: u64,
    pub ram_gb: u64,
    pub cpu_info: String,
    pub secure_boot_enabled: bool,
    pub bitlocker_enabled: bool,
}

// Disk information structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DiskInfo {
    pub name: String,
    pub size_gb: u64,
    pub free_space_gb: u64,
}

// Installation progress structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct InstallProgress {
    pub step: String,
    pub progress_percent: u8,
    pub current_step_index: u8,
    pub total_steps: u8,
}

// Staging result structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct StagingInfo {
    pub boot_partition_letter: String,
    pub linux_partition_number: u32,
}

// Rollback tracking structures
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct StagingState {
    pub timestamp: String,
    pub disk_index: u32,
    pub original_c_drive_size_mb: Option<u64>,
    pub efi_entries_before: Vec<String>,
    pub osworldboot_partition_number: Option<u32>,
    pub linux_partition_number: Option<u32>,
    pub osworldboot_letter: Option<String>,
    pub stage_completed: String, // "none", "partition", "download", "refind", "reboot"
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RollbackAction {
    pub description: String,
    pub success: bool,
    pub warning: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RollbackStatus {
    pub success: bool,
    pub actions: Vec<RollbackAction>,
    pub manual_steps: Vec<String>,
    pub log_path: String,
}

// Download progress event payload (emitted to frontend)
#[derive(Debug, Serialize, Clone)]
pub struct DownloadProgressEvent {
    pub percent: u8,
    pub stage: String,
}

// Download progress result structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DownloadProgress {
    pub percent: u8,
    pub stage: String,
    pub bytes_downloaded: u64,
    pub total_bytes: u64,
}

// ==================== Tauri Commands ====================

/// Set the installation type (Dual Boot or Replace Windows)
#[tauri::command]
fn set_install_type(install_type: String, state: State<AppState>) -> Result<()> {
    let mut config = state.config.lock().map_err(|e| {
        InstallerError::Unknown(format!("Failed to lock state: {}", e))
    })?;
    
    config.install_type = match install_type.as_str() {
        "dualboot" => Some(InstallType::DualBoot),
        "replace" => Some(InstallType::ReplaceWindows),
        _ => return Err(InstallerError::ValidationError(
            "Invalid install type".to_string()
        )),
    };
    
    Ok(())
}

/// Get the current installation configuration
#[tauri::command]
fn get_config(state: State<AppState>) -> Result<InstallConfig> {
    let config = state.config.lock().map_err(|e| {
        InstallerError::Unknown(format!("Failed to lock state: {}", e))
    })?;
    Ok(config.clone())
}

/// Save configuration to JSON file for next stage
#[tauri::command]
fn save_config_to_json(path: String, state: State<AppState>) -> Result<()> {
    let config = state.config.lock().map_err(|e| {
        InstallerError::Unknown(format!("Failed to lock state: {}", e))
    })?;
    
    let json = serde_json::to_string_pretty(&*config).map_err(|e| {
        InstallerError::Unknown(format!("Failed to serialize config: {}", e))
    })?;
    
    std::fs::write(&path, json).map_err(|e| {
        InstallerError::Unknown(format!("Failed to write config file: {}", e))
    })?;
    
    Ok(())
}

/// Detect system information (Windows version, RAM, CPU, etc.)
#[tauri::command]
async fn detect_system_info() -> Result<SystemInfo> {
    // Use sysinfo to get system information
    let mut sys = sysinfo::System::new_all();
    sys.refresh_all();
    
    // Get RAM (in GB)
    let ram_gb = sys.total_memory() / 1024 / 1024 / 1024;
    
    // Get CPU info
    let cpu_info = sys.cpus().first()
        .map(|cpu| cpu.brand().to_string())
        .unwrap_or_else(|| "Unknown CPU".to_string());
    
    // Get disk free space using Windows GetDiskFreeSpaceExW
    let disk_free_space_gb = get_disk_free_space().unwrap_or(0);
    
    // Detect Windows version from Registry
    let windows_version = detect_windows_version().await?;
    
    // Check Secure Boot status from Registry
    let secure_boot_enabled = check_secure_boot().unwrap_or(false);
    
    // Check BitLocker status via WMI
    let bitlocker_enabled = check_bitlocker().unwrap_or(false);
    
    Ok(SystemInfo {
        windows_version,
        disk_free_space_gb,
        ram_gb,
        cpu_info,
        secure_boot_enabled,
        bitlocker_enabled,
    })
}

/// Get list of available disks
#[tauri::command]
fn get_available_disks() -> Result<Vec<DiskInfo>> {
    #[cfg(windows)]
    {
        // Try WMI first
        match get_available_disks_wmi() {
            Ok(disks) if !disks.is_empty() => {
                eprintln!("[get_available_disks] WMI returned {} disks", disks.len());
                return Ok(disks);
            }
            Ok(_) => eprintln!("[get_available_disks] WMI returned empty, trying fallback"),
            Err(e) => eprintln!("[get_available_disks] WMI failed: {}, trying fallback", e),
        }

        // Fallback to wmic command
        get_available_disks_wmic()
    }
    #[cfg(not(windows))]
    {
        Ok(vec![
            DiskInfo {
                name: "Disk 0 (C:)".to_string(),
                size_gb: 512,
                free_space_gb: 200,
            },
            DiskInfo {
                name: "Disk 1 (D:)".to_string(),
                size_gb: 1024,
                free_space_gb: 800,
            },
        ])
    }
}

#[cfg(windows)]
fn get_available_disks_wmi() -> Result<Vec<DiskInfo>> {
    use wmi::{COMLibrary, WMIConnection};
    use serde::Deserialize;

    #[derive(Deserialize, Debug)]
    struct Win32LogicalDisk {
        #[serde(rename = "DeviceID")]
        device_id: String,
        #[serde(rename = "Size")]
        size: Option<u64>,
        #[serde(rename = "FreeSpace")]
        free_space: Option<u64>,
        #[serde(rename = "DriveType")]
        drive_type: u32,
    }

    let com = COMLibrary::new().map_err(|e| {
        InstallerError::SystemCheckFailed(format!("COM init failed: {}", e))
    })?;

    let wmi = WMIConnection::new(com).map_err(|e| {
        InstallerError::SystemCheckFailed(format!("WMI connection failed: {}", e))
    })?;

    let logical_disks: Vec<Win32LogicalDisk> = wmi
        .raw_query("SELECT * FROM Win32_LogicalDisk WHERE DriveType=3")
        .map_err(|e| InstallerError::SystemCheckFailed(format!("WMI query failed: {}", e)))?;

    let mut disks = Vec::new();
    for ld in logical_disks {
        if ld.drive_type != 3 {
            continue;
        }
        let size_gb = ld.size.map(|s| (s as u64) / (1024 * 1024 * 1024)).unwrap_or(0);
        let free_gb = ld.free_space.map(|f| (f as u64) / (1024 * 1024 * 1024)).unwrap_or(0);
        disks.push(DiskInfo {
            name: format!("{} Drive", ld.device_id),
            size_gb,
            free_space_gb: free_gb,
        });
    }

    Ok(disks)
}

#[cfg(windows)]
fn get_available_disks_wmic() -> Result<Vec<DiskInfo>> {
    println!("[get_available_disks] Starting");

    // Use wmic command - no COM needed, works in VMs
    let output = std::process::Command::new("cmd")
    .args(&["/c", "wmic logicaldisk get DeviceID,Size,FreeSpace,DriveType /format:csv"])
    .output()
    .map_err(|e| InstallerError::SystemCheckFailed(format!("wmic failed: {}", e)))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    eprintln!("[get_available_disks] wmic output:\n{}", stdout);
    println!("[get_available_disks] wmic output: {}", stdout);

    let mut disks = Vec::new();

    // Parse CSV lines
    for line in stdout.lines().skip(1) { // skip header
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() >= 5 {
            let name = parts[1].trim();
            let size = parts[2].trim();
            let free = parts[3].trim();
            let dtype = parts[4].trim();

            // Only fixed drives (type 3) with valid data
            if dtype == "3" && !size.is_empty() && size != "Size" {
                if let (Ok(total_bytes), Ok(free_bytes)) = (size.parse::<u64>(), free.parse::<u64>()) {
                    let total_gb = (total_bytes / (1024*1024*1024)) as u64;
                    let free_gb = (free_bytes / (1024*1024*1024)) as u64;

                    disks.push(DiskInfo {
                        name: format!("{} Drive", name),
                        size_gb: total_gb,           // NOT total_size
                        free_space_gb: free_gb,      // NOT free_space
                    });
                    println!("[get_available_disks] Found disk: {} {}GB total {}GB free", name, total_gb, free_gb);
                }
            }
        }
    }

    if disks.is_empty() {
        return Err(InstallerError::SystemCheckFailed("No disks found".to_string()));
    }

    Ok(disks)
    }




/// Validate and set user configuration
#[tauri::command]
fn set_user_config(
    username: String,
    computer_name: String,
    password: String,
    confirm_password: String,
    state: State<AppState>,
) -> Result<()> {
    // Validate username (lowercase only)
    if username != username.to_lowercase() {
        return Err(InstallerError::ValidationError(
            "Username must be lowercase only".to_string()
        ));
    }
    
    if username.len() < 3 {
        return Err(InstallerError::ValidationError(
            "Username must be at least 3 characters".to_string()
        ));
    }
    
    // Validate password (8+ characters)
    if password.len() < 8 {
        return Err(InstallerError::ValidationError(
            "Password must be at least 8 characters".to_string()
        ));
    }
    
    // Check password match
    if password != confirm_password {
        return Err(InstallerError::ValidationError(
            "Passwords do not match".to_string()
        ));
    }
    
    let mut config = state.config.lock().map_err(|e| {
        InstallerError::Unknown(format!("Failed to lock state: {}", e))
    })?;
    
    config.username = Some(username);
    config.computer_name = Some(computer_name);
    config.password = Some(password);
    
    Ok(())
}

/// Start installation process (legacy simulation — kept for compatibility)
#[tauri::command]
async fn start_installation(app: tauri::AppHandle) -> Result<()> {
    let steps = vec![
        "Downloading OS...",
        "Preparing Disk...",
        "Installing System...",
        "Finalizing...",
    ];
    
    for (i, step) in steps.iter().enumerate() {
        let progress = InstallProgress {
            step: step.to_string(),
            progress_percent: ((i + 1) as u8 * 100 / steps.len() as u8),
            current_step_index: i as u8,
            total_steps: steps.len() as u8,
        };
        
        // Emit progress event to frontend
        let _ = app.emit("install-progress", &progress);
        
        // Simulate work (in production, this would be actual installation steps)
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
    }
    
    Ok(())
}

/// Cancel installation
#[tauri::command]
fn cancel_installation() -> Result<()> {
    // In production, this would safely abort the installation process
    Ok(())
}

/// Calculate estimated installation time based on configuration
#[tauri::command]
fn calculate_estimated_time(linux_size_gb: u64) -> Result<String> {
    // Rough estimate: ~10 minutes base + 2 minutes per 10GB
    let minutes = 10 + (linux_size_gb / 10) * 2;
    Ok(format!("{} minutes", minutes))
}

// ==================== Staging Commands ====================

/// Prepare disk staging: shrink C:, create boot and Linux partitions.
/// Requires confirmation string "OSWORLD" for safety.
#[tauri::command]
fn prepare_staging(config: InstallConfig, confirmation: String) -> Result<StagingInfo> {
    if confirmation != "OSWORLD" {
        return Err(InstallerError::ValidationError(
            "Confirmation must be exactly OSWORLD".to_string()
        ));
    }

    #[cfg(windows)]
    {
        let linux_size_gb = config.linux_size_gb.ok_or_else(|| {
            InstallerError::ValidationError("Linux partition size not configured".to_string())
        })?;

        // Check BitLocker
        if check_bitlocker().unwrap_or(false) {
            return Err(InstallerError::SystemCheckFailed(
                "BitLocker is enabled. Please disable BitLocker before continuing.".to_string()
            ));
        }

        // Check UEFI
        if !is_uefi() {
            return Err(InstallerError::SystemCheckFailed(
                "System must be running in UEFI mode.".to_string()
            ));
        }

        // Check GPT
        let (disk_index, is_gpt) = get_system_disk_info()?;
        if !is_gpt {
            return Err(InstallerError::SystemCheckFailed(
                "System disk must use GPT partitioning. MBR is not supported.".to_string()
            ));
        }

        // Check free space on C:
        let free_gb = get_disk_free_space().unwrap_or(0);
        let required_gb = linux_size_gb + 2 + 10; // linux + boot + buffer
        if free_gb < required_gb {
            return Err(InstallerError::SystemCheckFailed(
                format!("Insufficient free space. Required: {} GB, Available: {} GB", required_gb, free_gb)
            ));
        }

        // Capture pre-staging state for rollback
        let c_size_output = run_powershell("(Get-Partition -DriveLetter C).Size")?;
        let c_size_mb = String::from_utf8_lossy(&c_size_output.stdout)
            .trim()
            .parse::<u64>()
            .map(|b| b / (1024 * 1024))
            .ok();

        let efi_output = run_powershell("bcdedit /enum firmware | Select-String -Pattern 'identifier'")?;
        let efi_entries: Vec<String> = String::from_utf8_lossy(&efi_output.stdout)
            .lines()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();

        let initial_state = StagingState {
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs()
                .to_string(),
            disk_index,
            original_c_drive_size_mb: c_size_mb,
            efi_entries_before: efi_entries,
            osworldboot_partition_number: None,
            linux_partition_number: None,
            osworldboot_letter: None,
            stage_completed: "none".to_string(),
        };
        save_staging_state(&initial_state)?;

        // Run diskpart to shrink and create partitions
        let shrink_mb = (linux_size_gb + 2) * 1024;
        let boot_mb = 2 * 1024;
        let linux_mb = linux_size_gb * 1024;

        run_diskpart_script(&format!(
            "select disk {}\n\
             select volume C\n\
             shrink desired={}\n\
             create partition primary size={}\n\
             format fs=fat32 quick label=OSWORLDBOOT\n\
             assign\n\
             create partition primary size={}\n\
             set id={{0FC63DAF-8483-4772-8E79-3D69D8477DE4}}\n",
            disk_index, shrink_mb, boot_mb, linux_mb
        ))?;

        // Locate created partitions
        let boot_letter = find_volume_by_label("OSWORLDBOOT")
            .ok_or_else(|| InstallerError::SystemCheckFailed(
                "Could not locate created boot partition".to_string()
            ))?;

        let linux_part_num = find_linux_partition_number(disk_index)
            .ok_or_else(|| InstallerError::SystemCheckFailed(
                "Could not locate created Linux partition".to_string()
            ))?;

        let osworld_part_num = find_partition_number_by_letter(&boot_letter)?;

        // Update state: partitioning complete
        let updated_state = StagingState {
            timestamp: initial_state.timestamp.clone(),
            disk_index,
            original_c_drive_size_mb: c_size_mb,
            efi_entries_before: initial_state.efi_entries_before.clone(),
            osworldboot_partition_number: Some(osworld_part_num),
            linux_partition_number: Some(linux_part_num),
            osworldboot_letter: Some(boot_letter.clone()),
            stage_completed: "partition".to_string(),
        };
        save_staging_state(&updated_state)?;

        Ok(StagingInfo {
            boot_partition_letter: boot_letter,
            linux_partition_number: linux_part_num,
        })
    }

    #[cfg(not(windows))]
    {
        let _ = (config, confirmation);
        Err(InstallerError::SystemCheckFailed(
            "Staging is only supported on Windows".to_string()
        ))
    }
}

/// Download Arch Linux ISO to the staging drive and write install-config.json.
#[tauri::command]
async fn download_and_stage_iso(
    target_drive_letter: String,
    config: InstallConfig,
    app: AppHandle,
) -> Result<DownloadProgress> {
    #[cfg(windows)]
    {
        let drive = target_drive_letter.trim_end_matches(':');
        let iso_path = format!("{}:\\arch.iso", drive);
        let config_path = format!("{}:\\install-config.json", drive);

        // Write config first
        let config_json = serde_json::to_string_pretty(&config).map_err(|e| {
            InstallerError::Unknown(format!("Failed to serialize config: {}", e))
        })?;
        tokio::fs::write(&config_path, config_json).await.map_err(|e| {
            InstallerError::InstallationError(format!("Failed to write config: {}", e))
        })?;

        // Download ISO with progress
        let url = "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso";
        let result = download_file_with_progress(url, &iso_path, &app).await?;

        // Verify file size (> 500 MB)
        let metadata = tokio::fs::metadata(&iso_path).await.map_err(|e| {
            InstallerError::InstallationError(format!("Failed to verify ISO: {}", e))
        })?;
        let size_mb = metadata.len() / (1024 * 1024);
        if size_mb < 500 {
            return Err(InstallerError::InstallationError(
                format!("Downloaded ISO is too small ({} MB)", size_mb)
            ));
        }

        // Extract kernel and initrd from the ISO so rEFInd can boot it directly
        let iso_label = extract_arch_iso_files(&iso_path, drive).await?;

        // Save ISO label for refind.conf generation
        let label_path = format!("{}:\\iso-label.txt", drive);
        tokio::fs::write(&label_path, &iso_label).await.map_err(|e| {
            InstallerError::InstallationError(format!("Failed to write ISO label: {}", e))
        })?;

        // Update staging state: download complete
        if let Some(mut state) = load_staging_state() {
            state.stage_completed = "download".to_string();
            let _ = save_staging_state(&state);
        }

        Ok(result)
    }
    #[cfg(not(windows))]
    {
        let _ = (target_drive_letter, config, app);
        Err(InstallerError::SystemCheckFailed(
            "ISO staging is only supported on Windows".to_string()
        ))
    }
}

/// Download and install rEFInd bootloader to the ESP.
#[tauri::command]
async fn install_refind() -> Result<()> {
    #[cfg(windows)]
    {
        let temp_dir = std::env::temp_dir().join("osworld-refind");
        let zip_path = temp_dir.join("refind.zip");
        tokio::fs::create_dir_all(&temp_dir).await.map_err(|e| {
            InstallerError::InstallationError(format!("Failed to create temp dir: {}", e))
        })?;

        // Download rEFInd bin zip
        let refind_url = "https://downloads.sourceforge.net/project/refind/0.14.2/refind-bin-0.14.2.zip";
        download_file_simple(refind_url, &zip_path).await?;

        // Extract zip
        let extract_dir = temp_dir.join("extracted");
        extract_zip(&zip_path, &extract_dir)?;

        // Find refind directory inside extraction
        let refind_dir = find_refind_dir(&extract_dir)?;

        // Assign temporary letter to ESP
        let esp_letter = assign_esp_letter()?;
        let esp_path = format!("{}:\\", esp_letter);

        // Create EFI directories
        let refind_efi_path = format!("{}EFI\\refind\\", esp_path);
        let refind_boot_path = format!("{}EFI\\BOOT\\", esp_path);
        std::fs::create_dir_all(&refind_efi_path).map_err(|e| {
            InstallerError::InstallationError(format!("Failed to create EFI dir: {}", e))
        })?;
        std::fs::create_dir_all(&refind_boot_path).map_err(|e| {
            InstallerError::InstallationError(format!("Failed to create BOOT dir: {}", e))
        })?;

        // Copy rEFInd EFI files
        let refind_efi_src = refind_dir.join("refind_x64.efi");
        std::fs::copy(&refind_efi_src, format!("{}refind_x64.efi", refind_efi_path)).map_err(|e| {
            InstallerError::InstallationError(format!("Failed to copy refind_x64.efi: {}", e))
        })?;
        std::fs::copy(&refind_efi_src, format!("{}bootx64.efi", refind_boot_path)).map_err(|e| {
            InstallerError::InstallationError(format!("Failed to copy fallback bootx64.efi: {}", e))
        })?;

        // Copy icons directory if present
        let icons_src = refind_dir.join("icons");
        if icons_src.exists() {
            let icons_dst = format!("{}icons\\", refind_efi_path);
            copy_dir_all(&icons_src, &icons_dst)?;
        }

        // Read ISO label from boot partition for archisolabel parameter
        let iso_label = find_volume_by_label("OSWORLDBOOT")
            .and_then(|letter| {
                let path = format!("{}\\iso-label.txt", letter.trim_end_matches(':'));
                std::fs::read_to_string(&path).ok()
            })
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "ARCH_202501".to_string());

        // Create refind.conf with proper EFI-style forward-slash paths
        // Includes both Installer and Recovery entries
        let config_content = format!(
            r#"timeout 10

menuentry "OSWorld Installer" {{
    icon \EFI\refind\icons\os_linux.png
    volume OSWORLDBOOT
    loader /arch/boot/x86_64/vmlinuz-linux
    initrd /arch/boot/x86_64/archiso.img
    options "img_dev=/dev/disk/by-label/OSWORLDBOOT img_loop=/arch.iso archisobasedir=arch archisolabel={}"
}}

menuentry "AltOS Recovery" {{
    icon \EFI\refind\icons\os_rescue.png
    volume OSWORLDBOOT
    loader /arch/boot/x86_64/vmlinuz-linux
    initrd /arch/boot/x86_64/archiso.img
    options "img_dev=/dev/disk/by-label/OSWORLDBOOT img_loop=/arch.iso archisobasedir=arch archisolabel={} rescue_mode=1"
}}
"#,
            iso_label, iso_label
        );
        std::fs::write(format!("{}refind.conf", refind_efi_path), config_content).map_err(|e| {
            InstallerError::InstallationError(format!("Failed to write refind.conf: {}", e))
        })?;

        // Add BCD entry
        add_refind_bcd_entry(&esp_letter)?;

        // Remove temporary ESP letter
        remove_esp_letter(&esp_letter)?;

        // Update staging state: rEFInd installed
        if let Some(mut state) = load_staging_state() {
            state.stage_completed = "refind".to_string();
            let _ = save_staging_state(&state);
        }

        Ok(())
    }
    #[cfg(not(windows))]
    {
        Err(InstallerError::SystemCheckFailed(
            "rEFInd installation is only supported on Windows".to_string()
        ))
    }
}

/// Reboot the computer into the installer.
#[tauri::command]
fn reboot_to_installer() -> Result<()> {
    #[cfg(windows)]
    {
        std::process::Command::new("shutdown")
            .args(&["/r", "/t", "5", "/c", "Rebooting to OSWorld Installer..."])
            .spawn()
            .map_err(|e| InstallerError::SystemCheckFailed(
                format!("Failed to initiate reboot: {}", e)
            ))?;
        Ok(())
    }
    #[cfg(not(windows))]
    {
        Err(InstallerError::SystemCheckFailed(
            "Reboot is only supported on Windows".to_string()
        ))
    }
}

// ==================== Helper Functions ====================

#[cfg(windows)]
fn to_wide(s: &str) -> Vec<u16> {
    use std::os::windows::ffi::OsStrExt;
    std::ffi::OsStr::new(s).encode_wide().chain(Some(0)).collect()
}

#[cfg(windows)]
fn reg_query_string(hkey: *mut std::ffi::c_void, subkey: &str, value: &str) -> Option<String> {
    use windows_sys::Win32::System::Registry::{
        RegOpenKeyExW, RegQueryValueExW, RegCloseKey, KEY_READ,
    };

    let subkey_wide = to_wide(subkey);
    let value_wide = to_wide(value);
    let mut h: *mut std::ffi::c_void = std::ptr::null_mut();

    let status = unsafe {
        RegOpenKeyExW(hkey, subkey_wide.as_ptr(), 0, KEY_READ, &mut h)
    };

    if status != 0 {
        return None;
    }

    let mut buf_size: u32 = 0;

    unsafe {
        RegQueryValueExW(
            h,
            value_wide.as_ptr(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            &mut buf_size,
        );
    }

    if buf_size == 0 || buf_size > 4096 {
        unsafe { RegCloseKey(h) };
        return None;
    }

    let mut buf = vec![0u8; buf_size as usize];
    let status = unsafe {
        RegQueryValueExW(
            h,
            value_wide.as_ptr(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            buf.as_mut_ptr(),
            &mut buf_size,
        )
    };

    unsafe { RegCloseKey(h) };

    if status != 0 {
        return None;
    }

    let u16_slice = unsafe {
        std::slice::from_raw_parts(buf.as_ptr() as *const u16, buf.len() / 2)
    };

    let u16_vec: Vec<u16> = u16_slice.iter().copied().take_while(|&c| c != 0).collect();
    String::from_utf16(&u16_vec).ok()
}

#[cfg(windows)]
fn reg_query_dword(hkey: *mut std::ffi::c_void, subkey: &str, value: &str) -> Option<u32> {
    use windows_sys::Win32::System::Registry::{
        RegOpenKeyExW, RegQueryValueExW, RegCloseKey, KEY_READ,
    };

    let subkey_wide = to_wide(subkey);
    let value_wide = to_wide(value);
    let mut h: *mut std::ffi::c_void = std::ptr::null_mut();

    let status = unsafe {
        RegOpenKeyExW(hkey, subkey_wide.as_ptr(), 0, KEY_READ, &mut h)
    };

    if status != 0 {
        return None;
    }

    let mut data: u32 = 0;
    let mut data_size: u32 = std::mem::size_of::<u32>() as u32;
    let mut data_type: u32 = 0;

    let status = unsafe {
        RegQueryValueExW(
            h,
            value_wide.as_ptr(),
            std::ptr::null_mut(),
            &mut data_type,
            &mut data as *mut u32 as *mut u8,
            &mut data_size,
        )
    };

    unsafe { RegCloseKey(h) };

    if status != 0 || data_type != 4 {
        // 4 = REG_DWORD
        return None;
    }

    Some(data)
}

async fn detect_windows_version() -> Result<String> {
    #[cfg(windows)]
    {
        let product_name = reg_query_string(
            windows_sys::Win32::System::Registry::HKEY_LOCAL_MACHINE as *mut c_void,
            r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "ProductName",
        )
        .unwrap_or_else(|| "Windows".to_string());

        let display_version = reg_query_string(
            windows_sys::Win32::System::Registry::HKEY_LOCAL_MACHINE as *mut c_void,
            r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "DisplayVersion",
        );

        let release_id = reg_query_string(
            windows_sys::Win32::System::Registry::HKEY_LOCAL_MACHINE as *mut c_void,
            r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "ReleaseId",
        );

        let version = match (display_version, release_id) {
            (Some(dv), _) => format!("{} ({})", product_name.trim(), dv.trim()),
            (None, Some(ri)) => format!("{} ({})", product_name.trim(), ri.trim()),
            _ => product_name.trim().to_string(),
        };

        Ok(version)
    }
    #[cfg(not(windows))]
    {
        Ok("Windows 11 Pro (23H2)".to_string())
    }
}

fn get_disk_free_space() -> Option<u64> {
    #[cfg(windows)]
    {
        use windows_sys::Win32::Storage::FileSystem::GetDiskFreeSpaceExW;

        let path = to_wide("C:\\");
        let mut free_bytes: u64 = 0;

        let result = unsafe {
            GetDiskFreeSpaceExW(
                path.as_ptr(),
                &mut free_bytes,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
            )
        };

        if result == 0 {
            return None;
        }

        Some(free_bytes / (1024 * 1024 * 1024))
    }
    #[cfg(not(windows))]
    {
        Some(250)
    }
}

fn check_secure_boot() -> Option<bool> {
    #[cfg(windows)]
    {
        let val = reg_query_dword(
            windows_sys::Win32::System::Registry::HKEY_LOCAL_MACHINE as *mut c_void,
            r"SYSTEM\CurrentControlSet\Control\SecureBoot\State",
            "UEFISecureBootEnabled",
        );
        Some(val.unwrap_or(0) != 0)
    }
    #[cfg(not(windows))]
    {
        Some(false)
    }
}

fn check_bitlocker() -> Option<bool> {
    #[cfg(windows)]
    {
        use wmi::{COMLibrary, WMIConnection};
        use serde::Deserialize;

        #[derive(Deserialize, Debug)]
        struct Win32EncryptableVolume {
            #[serde(rename = "DriveLetter")]
            _drive_letter: String,
            #[serde(rename = "ProtectionStatus")]
            protection_status: u32,
        }

        let com = COMLibrary::new().ok()?;
        let wmi = WMIConnection::new(com).ok()?;

        let volumes: Vec<Win32EncryptableVolume> = wmi
            .raw_query("SELECT * FROM Win32_EncryptableVolume WHERE DriveLetter='C:'")
            .ok()?;

        if volumes.is_empty() {
            return Some(false);
        }

        // 0 = Unprotected, 1 = Protected, 2 = Unknown
        Some(volumes[0].protection_status == 1)
    }
    #[cfg(not(windows))]
    {
        Some(false)
    }
}

// ==================== Staging Helpers ====================

#[cfg(windows)]
fn run_powershell(command: &str) -> Result<std::process::Output> {
    let output = std::process::Command::new("powershell")
        .args(&["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command])
        .output()
        .map_err(|e| InstallerError::SystemCheckFailed(format!("PowerShell execution failed: {}", e)))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(InstallerError::SystemCheckFailed(format!("PowerShell error: {}", stderr)));
    }

    Ok(output)
}

#[cfg(windows)]
fn is_uefi() -> bool {
    let output = run_powershell(
        "if (Get-Partition | Where-Object { $_.Type -eq 'System' }) { Write-Output 'UEFI' } else { Write-Output 'BIOS' }"
    );
    match output {
        Ok(o) => String::from_utf8_lossy(&o.stdout).trim() == "UEFI",
        Err(_) => false,
    }
}

#[cfg(windows)]
fn get_system_disk_info() -> Result<(u32, bool)> {
    let output = run_powershell("(Get-Partition -DriveLetter C).DiskNumber")?;
    let disk_index = String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse::<u32>()
        .map_err(|_| InstallerError::SystemCheckFailed("Could not parse system disk index".to_string()))?;

    let output = run_powershell(&format!("(Get-Disk -Number {}).PartitionStyle", disk_index))?;
    let style = String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse::<u32>()
        .map_err(|_| InstallerError::SystemCheckFailed("Could not parse partition style".to_string()))?;

    Ok((disk_index, style == 1)) // 1 = GPT
}

#[cfg(windows)]
fn save_staging_state(state: &StagingState) -> Result<()> {
    let state_dir = std::path::Path::new(r"C:\ProgramData\OSWorld");
    let state_path = state_dir.join("staging-state.json");
    let log_dir = state_dir.join("logs");
    
    std::fs::create_dir_all(&state_dir).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to create state dir: {}", e))
    })?;
    std::fs::create_dir_all(&log_dir).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to create log dir: {}", e))
    })?;
    
    let json = serde_json::to_string_pretty(state).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to serialize state: {}", e))
    })?;
    
    std::fs::write(&state_path, json).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to write state file: {}", e))
    })?;
    
    Ok(())
}

#[cfg(windows)]
fn load_staging_state() -> Option<StagingState> {
    let state_path = std::path::Path::new(r"C:\ProgramData\OSWorld\staging-state.json");
    if !state_path.exists() {
        return None;
    }
    let content = std::fs::read_to_string(state_path).ok()?;
    serde_json::from_str(&content).ok()
}

#[cfg(windows)]
fn append_rollback_log(message: &str) {
    let log_dir = std::path::Path::new(r"C:\ProgramData\OSWorld\logs");
    let _ = std::fs::create_dir_all(log_dir);
    let log_path = log_dir.join("rollback.log");
    let now = std::time::SystemTime::now();
    let since_epoch = now.duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
    let timestamp = format!("{}.{:03}", since_epoch.as_secs(), since_epoch.subsec_millis());
    let line = format!("[{}] {}\n", timestamp, message);
    let _ = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .and_then(|mut f| { use std::io::Write; f.write_all(line.as_bytes()) });
}

#[cfg(windows)]
fn run_diskpart_script(script: &str) -> Result<String> {
    let temp_path = std::env::temp_dir().join("osworld_diskpart.txt");
    std::fs::write(&temp_path, script).map_err(|e| {
        InstallerError::SystemCheckFailed(format!("Failed to write diskpart script: {}", e))
    })?;

    let output = std::process::Command::new("diskpart")
        .arg("/s")
        .arg(&temp_path)
        .output()
        .map_err(|e| InstallerError::SystemCheckFailed(format!("diskpart execution failed: {}", e)))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success()
        || stdout.to_lowercase().contains("diskpart has encountered an error")
        || stderr.to_lowercase().contains("error")
    {
        return Err(InstallerError::SystemCheckFailed(
            format!("diskpart failed. stdout: {}  stderr: {}", stdout, stderr)
        ));
    }

    Ok(stdout)
}

#[cfg(windows)]
fn find_volume_by_label(label: &str) -> Option<String> {
    let output = run_powershell(&format!(
        "(Get-Volume -FileSystemLabel '{}').DriveLetter",
        label
    )).ok()?;
    let letter = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if letter.is_empty() {
        None
    } else {
        Some(format!("{}:", letter))
    }
}

#[cfg(windows)]
fn find_linux_partition_number(disk_index: u32) -> Option<u32> {
    let output = run_powershell(&format!(
        "(Get-Partition -DiskNumber {} | Sort-Object PartitionNumber -Descending | Select-Object -First 1).PartitionNumber",
        disk_index
    )).ok()?;
    String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse::<u32>()
        .ok()
}

#[cfg(windows)]
fn find_partition_number_by_letter(letter: &str) -> Result<u32> {
    let clean = letter.trim_end_matches(':');
    let output = run_powershell(&format!(
        "(Get-Partition | Where-Object {{ $_.DriveLetter -eq '{}' }}).PartitionNumber",
        clean
    ))?;
    String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse::<u32>()
        .map_err(|_| InstallerError::SystemCheckFailed(
            format!("Could not find partition number for drive {}", letter)
        ))
}

/// Mount the Arch ISO, extract kernel and initrd to the boot partition,
/// and return the ISO filesystem label.
#[cfg(windows)]
async fn extract_arch_iso_files(iso_path: &str, dest_drive: &str) -> Result<String> {
    let drive = dest_drive.trim_end_matches(':');
    let dest_dir = format!("{}:\\arch\\boot\\x86_64", drive);

    tokio::fs::create_dir_all(&dest_dir).await.map_err(|e| {
        InstallerError::InstallationError(format!("Failed to create arch boot dir: {}", e))
    })?;

    let ps_script = format!(
        "$iso = Mount-DiskImage -ImagePath '{}' -PassThru; \
         Start-Sleep -Milliseconds 800; \
         $vol = $iso | Get-Volume; \
         $letter = $vol.DriveLetter; \
         $label = $vol.FileSystemLabel; \
         Copy-Item -Path \"${{letter}}:\\arch\\boot\\x86_64\\vmlinuz-linux\" -Destination \"{}\\vmlinuz-linux\" -Force; \
         Copy-Item -Path \"${{letter}}:\\arch\\boot\\x86_64\\archiso.img\" -Destination \"{}\\archiso.img\" -Force; \
         Dismount-DiskImage -ImagePath '{}'; \
         Write-Output \"LABEL=$label\"",
        iso_path,
        dest_dir,
        dest_dir,
        iso_path
    );

    let output = run_powershell(&ps_script)?;
    let stdout = String::from_utf8_lossy(&output.stdout);

    let label = stdout
        .lines()
        .find(|l| l.starts_with("LABEL="))
        .and_then(|l| l.strip_prefix("LABEL="))
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "ARCH_202501".to_string());

    let vmlinuz_path = format!("{}\\vmlinuz-linux", dest_dir);
    let initrd_path = format!("{}\\archiso.img", dest_dir);

    if !std::path::Path::new(&vmlinuz_path).exists() {
        return Err(InstallerError::InstallationError(
            "Failed to extract vmlinuz-linux from ISO".to_string()
        ));
    }
    if !std::path::Path::new(&initrd_path).exists() {
        return Err(InstallerError::InstallationError(
            "Failed to extract archiso.img from ISO".to_string()
        ));
    }

    Ok(label)
}

#[cfg(windows)]
async fn download_file_with_progress(
    url: &str,
    path: &str,
    app: &AppHandle,
) -> Result<DownloadProgress> {
    use futures_util::StreamExt;

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(3600))
        .build()
        .map_err(|e| InstallerError::InstallationError(format!("HTTP client error: {}", e)))?;

    let response = client.get(url).send().await.map_err(|e| {
        InstallerError::InstallationError(format!("Download request failed: {}", e))
    })?;

    let total_bytes = response.content_length().unwrap_or(0);
    let mut file = tokio::fs::File::create(path).await.map_err(|e| {
        InstallerError::InstallationError(format!("Failed to create file: {}", e))
    })?;

    let mut stream = response.bytes_stream();
    let mut downloaded: u64 = 0;
    let mut last_percent: u8 = 0;

    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| {
            InstallerError::InstallationError(format!("Download stream error: {}", e))
        })?;
        tokio::io::AsyncWriteExt::write_all(&mut file, &chunk).await.map_err(|e| {
            InstallerError::InstallationError(format!("Failed to write file: {}", e))
        })?;
        downloaded += chunk.len() as u64;

        if total_bytes > 0 {
            let percent = ((downloaded * 100) / total_bytes) as u8;
            if percent >= last_percent + 5 {
                last_percent = percent;
                let _ = app.emit("download-progress", DownloadProgressEvent {
                    percent,
                    stage: "Downloading Arch Linux ISO...".to_string(),
                });
            }
        }
    }

    tokio::io::AsyncWriteExt::flush(&mut file).await.map_err(|e| {
        InstallerError::InstallationError(format!("Failed to flush file: {}", e))
    })?;

    Ok(DownloadProgress {
        percent: 100,
        stage: "Download complete".to_string(),
        bytes_downloaded: downloaded,
        total_bytes,
    })
}

#[cfg(windows)]
async fn download_file_simple(url: &str, path: &std::path::Path) -> Result<()> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(300))
        .build()
        .map_err(|e| InstallerError::InstallationError(format!("HTTP client error: {}", e)))?;

    let response = client.get(url).send().await.map_err(|e| {
        InstallerError::InstallationError(format!("Download request failed: {}", e))
    })?;

    let bytes = response.bytes().await.map_err(|e| {
        InstallerError::InstallationError(format!("Download failed: {}", e))
    })?;

    tokio::fs::write(path, &bytes).await.map_err(|e| {
        InstallerError::InstallationError(format!("Failed to write file: {}", e))
    })?;

    Ok(())
}

#[cfg(windows)]
fn extract_zip(zip_path: &std::path::Path, dest_dir: &std::path::Path) -> Result<()> {
    let file = std::fs::File::open(zip_path).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to open zip: {}", e))
    })?;
    let mut archive = zip::ZipArchive::new(file).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to read zip: {}", e))
    })?;

    archive.extract(dest_dir).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to extract zip: {}", e))
    })?;

    Ok(())
}

#[cfg(windows)]
fn find_refind_dir(extract_dir: &std::path::Path) -> Result<std::path::PathBuf> {
    for entry in std::fs::read_dir(extract_dir).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to read extraction dir: {}", e))
    })? {
        let entry = entry.map_err(|e| {
            InstallerError::InstallationError(format!("Dir entry error: {}", e))
        })?;
        let refind_subdir = entry.path().join("refind");
        if refind_subdir.exists() {
            return Ok(refind_subdir);
        }
    }
    Err(InstallerError::InstallationError(
        "Could not find refind directory in extracted archive".to_string()
    ))
}

#[cfg(windows)]
fn assign_esp_letter() -> Result<String> {
    let output = run_powershell(
        "$letters = 83..90 | ForEach-Object { [char]$_ }; \
         $available = $letters | Where-Object { -not (Test-Path \"$($_):\") } | Select-Object -First 1; \
         if (-not $available) { throw 'No available drive letters' }; \
         $esp = Get-Partition | Where-Object { $_.Type -eq 'System' } | Select-Object -First 1; \
         if (-not $esp) { throw 'No ESP found' }; \
         Add-PartitionAccessPath -DiskNumber $esp.DiskNumber -PartitionNumber $esp.PartitionNumber -AccessPath \"$($available):\" -ErrorAction Stop; \
         Write-Output $available"
    )?;

    let letter = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if letter.is_empty() {
        return Err(InstallerError::InstallationError("Failed to assign ESP letter".to_string()));
    }
    Ok(format!("{}:", letter))
}

#[cfg(windows)]
fn remove_esp_letter(letter: &str) -> Result<()> {
    let l = letter.trim_end_matches(':');
    run_powershell(&format!(
        "$esp = Get-Partition | Where-Object {{ $_.AccessPaths -contains '{}:\' }} | Select-Object -First 1; \
         if ($esp) {{ Remove-PartitionAccessPath -DiskNumber $esp.DiskNumber -PartitionNumber $esp.PartitionNumber -AccessPath '{}:\' -ErrorAction Stop }}",
        l, l
    ))?;
    Ok(())
}

#[cfg(windows)]
fn add_refind_bcd_entry(esp_letter: &str) -> Result<()> {
    let l = esp_letter.trim_end_matches(':');

    let output = std::process::Command::new("bcdedit")
        .args(&["/copy", "{current}", "/d", "OSWorld Installer (rEFInd)"])
        .output()
        .map_err(|e| InstallerError::InstallationError(format!("bcdedit failed: {}", e)))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let guid = stdout
        .split('{')
        .nth(1)
        .and_then(|s| s.split('}').next())
        .map(|s| format!("{{{}}}", s))
        .ok_or_else(|| InstallerError::InstallationError(
            "Failed to parse bcdedit GUID".to_string()
        ))?;

    let commands = vec![
        format!("bcdedit /set {} path \\EFI\\refind\\refind_x64.efi", guid),
        format!("bcdedit /set {} device partition={}:", guid, l),
        format!("bcdedit /displayorder {} /addfirst", guid),
    ];

    for cmd in commands {
        let parts: Vec<&str> = cmd.split_whitespace().collect();
        let status = std::process::Command::new(parts[0])
            .args(&parts[1..])
            .status()
            .map_err(|e| InstallerError::InstallationError(format!("bcdedit command failed: {}", e)))?;

        if !status.success() {
            return Err(InstallerError::InstallationError(
                format!("bcdedit command failed: {}", cmd)
            ));
        }
    }

    Ok(())
}

#[cfg(windows)]
fn copy_dir_all(src: &std::path::Path, dst: &str) -> Result<()> {
    std::fs::create_dir_all(dst).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to create dir {}: {}", dst, e))
    })?;

    for entry in std::fs::read_dir(src).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to read dir: {}", e))
    })? {
        let entry = entry.map_err(|e| {
            InstallerError::InstallationError(format!("Dir entry error: {}", e))
        })?;
        let src_path = entry.path();
        let file_name = entry.file_name();
        let dst_path = std::path::Path::new(dst).join(&file_name);

        if src_path.is_dir() {
            copy_dir_all(&src_path, dst_path.to_str().unwrap_or(""))?;
        } else {
            std::fs::copy(&src_path, &dst_path).map_err(|e| {
                InstallerError::InstallationError(format!("Failed to copy file: {}", e))
            })?;
        }
    }
    Ok(())
}

/// Write install-config.json to the staging drive without downloading ISO.
#[tauri::command]
async fn write_config(config: InstallConfig, drive: String) -> Result<()> {
    #[cfg(windows)]
    {
        let drive_clean = drive.trim_end_matches(':');
        let config_path = format!("{}:\\install-config.json", drive_clean);
        let config_json = serde_json::to_string_pretty(&config).map_err(|e| {
            InstallerError::Unknown(format!("Failed to serialize config: {}", e))
        })?;
        tokio::fs::write(&config_path, config_json).await.map_err(|e| {
            InstallerError::InstallationError(format!("Failed to write config: {}", e))
        })?;
        Ok(())
    }
    #[cfg(not(windows))]
    {
        let _ = (config, drive);
        Err(InstallerError::SystemCheckFailed(
            "write_config is only supported on Windows".to_string()
        ))
    }
}

/// Download Arch Linux ISO to the staging drive with progress events.
#[tauri::command]
async fn download_iso(drive: String, app: AppHandle) -> Result<DownloadProgress> {
    #[cfg(windows)]
    {
        let drive_clean = drive.trim_end_matches(':');
        let iso_path = format!("{}:\\arch.iso", drive_clean);
        let url = "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso";
        download_file_with_progress(url, &iso_path, &app).await
    }
    #[cfg(not(windows))]
    {
        let _ = (drive, app);
        Err(InstallerError::SystemCheckFailed(
            "download_iso is only supported on Windows".to_string()
        ))
    }
}

/// Remove staging partitions and restore disk to pre-installation state.
/// Requires typed confirmation "OSWORLD".
#[tauri::command]
fn cleanup_staging(confirmation: String) -> Result<()> {
    if confirmation != "OSWORLD" {
        return Err(InstallerError::ValidationError(
            "Confirmation must be exactly OSWORLD".to_string()
        ));
    }

    #[cfg(windows)]
    {
        // Find OSWORLDBOOT partition
        let osworld_label = find_volume_by_label("OSWORLDBOOT");
        if osworld_label.is_none() {
            return Err(InstallerError::SystemCheckFailed(
                "OSWORLDBOOT partition not found. Nothing to clean up.".to_string()
            ));
        }

        // Find Linux raw partition (last partition on system disk)
        let disk_info = get_system_disk_info()?;
        let disk_index = disk_info.0;

        // Remove Linux partition (last one on disk)
        let linux_part = find_linux_partition_number(disk_index);
        if linux_part.is_some() {
            run_diskpart_script(&format!(
                "select disk {}\nselect partition {}\ndelete partition override\n",
                disk_index,
                linux_part.unwrap()
            ))?;
        }

        // Remove OSWORLDBOOT partition
        let osworld_letter = osworld_label.unwrap();
        let osworld_letter_clean = osworld_letter.trim_end_matches(':');

        // Find partition number by drive letter
        let output = run_powershell(&format!(
            "(Get-Partition | Where-Object {{ $_.DriveLetter -eq '{}' }}).PartitionNumber",
            osworld_letter_clean
        ))?;
        let part_num = String::from_utf8_lossy(&output.stdout)
            .trim()
            .parse::<u32>()
            .map_err(|_| InstallerError::InstallationError(
                "Could not parse OSWORLDBOOT partition number".to_string()
            ))?;

        run_diskpart_script(&format!(
            "select disk {}\nselect partition {}\ndelete partition override\n",
            disk_index, part_num
        ))?;

        // Expand C: drive to reclaim space
        run_diskpart_script(&format!(
            "select disk {}\nselect volume C\nextend\n",
            disk_index
        ))?;

        // Remove rEFInd from EFI
        let esp_letter = assign_esp_letter()?;
        let esp_path = format!("{}:\\", esp_letter);
        let refind_path = format!("{}EFI\\refind\\", esp_path);
        let refind_boot_path = format!("{}EFI\\BOOT\\", esp_path);

        // Remove rEFInd directories (ignore errors)
        let _ = std::fs::remove_dir_all(&refind_path);
        let _ = std::fs::remove_dir_all(&refind_boot_path);

        remove_esp_letter(&esp_letter)?;

        // Clean up BCD entries for OSWorld Installer
        let output = std::process::Command::new("bcdedit")
            .args(&["/enum"])
            .output()
            .map_err(|e| InstallerError::InstallationError(format!("bcdedit enum failed: {}", e)))?;
        let stdout = String::from_utf8_lossy(&output.stdout);
        for line in stdout.lines() {
            if line.contains("OSWorld Installer") {
                if let Some(guid) = line.split('{').nth(1).and_then(|s| s.split('}').next()) {
                    let full_guid = format!("{{{}}}", guid);
                    let _ = std::process::Command::new("bcdedit")
                        .args(&["/delete", &full_guid, "/cleanup"])
                        .status();
                }
            }
        }

        Ok(())
    }
    #[cfg(not(windows))]
    {
        let _ = confirmation;
        Err(InstallerError::SystemCheckFailed(
            "cleanup_staging is only supported on Windows".to_string()
        ))
    }
}

/// Rollback staging changes automatically.
/// Reads staging-state.json and reverses every change made.
/// If state file is missing, performs best-effort scan and rollback.
#[tauri::command]
fn rollback_staging(confirmation: String) -> Result<RollbackStatus> {
    if confirmation != "ROLLBACK" {
        return Err(InstallerError::ValidationError(
            "Confirmation must be exactly ROLLBACK".to_string()
        ));
    }

    #[cfg(windows)]
    {
        let mut actions: Vec<RollbackAction> = Vec::new();
        let mut manual_steps: Vec<String> = Vec::new();

        append_rollback_log("Rollback initiated.");

        let state = match load_staging_state() {
            Some(s) => {
                append_rollback_log(&format!("Loaded state. Stage completed: {}", s.stage_completed));
                s
            }
            None => {
                append_rollback_log("No state file found. Attempting best-effort rollback.");
                manual_steps.push("No staging state file found. Manual cleanup may be required.".to_string());
                // Best-effort: try to find and remove OSWORLDBOOT
                let disk_info = get_system_disk_info()?;
                StagingState {
                    timestamp: "0".to_string(),
                    disk_index: disk_info.0,
                    original_c_drive_size_mb: None,
                    efi_entries_before: vec![],
                    osworldboot_partition_number: None,
                    linux_partition_number: None,
                    osworldboot_letter: None,
                    stage_completed: "unknown".to_string(),
                }
            }
        };

        let disk_index = state.disk_index;

        // Step 1: Remove BCD entries for OSWorld Installer / rEFInd
        append_rollback_log("Removing BCD entries...");
        let output = std::process::Command::new("bcdedit")
            .args(&["/enum"])
            .output();
        if let Ok(o) = output {
            let stdout = String::from_utf8_lossy(&o.stdout);
            for line in stdout.lines() {
                if line.contains("OSWorld Installer") || line.contains("rEFInd") {
                    if let Some(guid) = line.split('{').nth(1).and_then(|s| s.split('}').next()) {
                        let full_guid = format!("{{{}}}", guid);
                        let del_result = std::process::Command::new("bcdedit")
                            .args(&["/delete", &full_guid, "/cleanup"])
                            .status();
                        if del_result.map(|s| s.success()).unwrap_or(false) {
                            actions.push(RollbackAction {
                                description: format!("Removed BCD entry: {}", full_guid),
                                success: true,
                                warning: None,
                            });
                        } else {
                            actions.push(RollbackAction {
                                description: format!("Failed to remove BCD entry: {}", full_guid),
                                success: false,
                                warning: Some("You may need to remove this entry manually with bcdedit".to_string()),
                            });
                        }
                    }
                }
            }
        }

        // Step 2: Restore Windows Boot Manager as default
        append_rollback_log("Restoring Windows Boot Manager...");
        let win_boot_result = run_powershell(
            "$bootmgr = bcdedit /enum firmware | Select-String -Pattern 'bootmgr' | Select-Object -First 1; \
             if ($bootmgr) { $guid = ($bootmgr -split '\\s+')[1]; bcdedit /displayorder $guid /addfirst | Out-Null; Write-Output 'OK' } else { Write-Output 'MISSING' }"
        );
        match win_boot_result {
            Ok(o) if String::from_utf8_lossy(&o.stdout).trim() == "OK" => {
                actions.push(RollbackAction {
                    description: "Restored Windows Boot Manager as default".to_string(),
                    success: true,
                    warning: None,
                });
            }
            _ => {
                actions.push(RollbackAction {
                    description: "Could not restore Windows Boot Manager automatically".to_string(),
                    success: false,
                    warning: Some("Use BIOS/UEFI settings to select Windows Boot Manager manually".to_string()),
                });
                manual_steps.push("Select Windows Boot Manager in your UEFI firmware settings.".to_string());
            }
        }

        // Step 3: Remove rEFInd files from EFI
        append_rollback_log("Removing rEFInd from EFI...");
        if let Ok(esp_letter) = assign_esp_letter() {
            let esp_path = format!("{}:\\", esp_letter);
            let refind_path = format!("{}EFI\\refind\\", esp_path);
            let refind_boot_path = format!("{}EFI\\BOOT\\", esp_path);
            let _ = std::fs::remove_dir_all(&refind_path);
            let _ = std::fs::remove_dir_all(&refind_boot_path);
            let _ = remove_esp_letter(&esp_letter);
            actions.push(RollbackAction {
                description: "Removed rEFInd files from EFI System Partition".to_string(),
                success: true,
                warning: None,
            });
        } else {
            actions.push(RollbackAction {
                description: "Could not mount EFI to remove rEFInd files".to_string(),
                success: false,
                warning: Some("You may need to remove \\EFI\\refind manually".to_string()),
            });
        }

        // Step 4: Remove OSWORLDBOOT partition
        append_rollback_log("Removing OSWORLDBOOT partition...");
        let osworld_part = state.osworldboot_partition_number
            .or_else(|| {
                let output = run_powershell(&format!(
                    "(Get-Partition -DiskNumber {} | Where-Object {{ (Get-Volume -Partition $_).FileSystemLabel -eq 'OSWORLDBOOT' }}).PartitionNumber",
                    disk_index
                )).ok()?;
                String::from_utf8_lossy(&output.stdout).trim().parse::<u32>().ok()
            });

        if let Some(part_num) = osworld_part {
            let del_result = run_diskpart_script(&format!(
                "select disk {}\nselect partition {}\ndelete partition override\n",
                disk_index, part_num
            ));
            match del_result {
                Ok(_) => {
                    actions.push(RollbackAction {
                        description: format!("Deleted OSWORLDBOOT partition {}", part_num),
                        success: true,
                        warning: None,
                    });
                }
                Err(e) => {
                    actions.push(RollbackAction {
                        description: format!("Failed to delete OSWORLDBOOT partition: {}", e),
                        success: false,
                        warning: Some("Use Disk Management to delete the OSWORLDBOOT partition".to_string()),
                    });
                    manual_steps.push("Delete the OSWORLDBOOT partition in Windows Disk Management.".to_string());
                }
            }
        } else {
            actions.push(RollbackAction {
                description: "OSWORLDBOOT partition not found (may already be removed)".to_string(),
                success: true,
                warning: None,
            });
        }

        // Step 5: Remove raw Linux partition
        append_rollback_log("Removing Linux partition...");
        let linux_part = state.linux_partition_number
            .or_else(|| find_linux_partition_number(disk_index));

        if let Some(part_num) = linux_part {
            // Make sure it's not the same as OSWORLDBOOT
            if Some(part_num) != osworld_part {
                let del_result = run_diskpart_script(&format!(
                    "select disk {}\nselect partition {}\ndelete partition override\n",
                    disk_index, part_num
                ));
                match del_result {
                    Ok(_) => {
                        actions.push(RollbackAction {
                            description: format!("Deleted Linux partition {}", part_num),
                            success: true,
                            warning: None,
                        });
                    }
                    Err(e) => {
                        actions.push(RollbackAction {
                            description: format!("Failed to delete Linux partition: {}", e),
                            success: false,
                            warning: Some("Use Disk Management to delete the raw Linux partition".to_string()),
                        });
                        manual_steps.push("Delete the raw Linux partition in Windows Disk Management.".to_string());
                    }
                }
            }
        } else {
            actions.push(RollbackAction {
                description: "Linux partition not found (may already be removed)".to_string(),
                success: true,
                warning: None,
            });
        }

        // Step 6: Expand C: drive
        append_rollback_log("Expanding C: drive...");
        let extend_result = run_diskpart_script(&format!(
            "select disk {}\nselect volume C\nextend\n",
            disk_index
        ));
        match extend_result {
            Ok(_) => {
                actions.push(RollbackAction {
                    description: "Expanded C: drive to reclaim space".to_string(),
                    success: true,
                    warning: None,
                });
            }
            Err(_) => {
                actions.push(RollbackAction {
                    description: "Could not automatically expand C: drive".to_string(),
                    success: false,
                    warning: Some("You can expand C: manually in Disk Management".to_string()),
                });
                manual_steps.push("Right-click C: in Disk Management and select 'Extend Volume' to reclaim space.".to_string());
            }
        }

        // Step 7: Clean up state file
        let state_path = std::path::Path::new(r"C:\ProgramData\OSWorld\staging-state.json");
        if state_path.exists() {
            let _ = std::fs::remove_file(state_path);
        }

        append_rollback_log("Rollback complete.");

        let all_success = actions.iter().all(|a| a.success) && manual_steps.is_empty();

        Ok(RollbackStatus {
            success: all_success,
            actions,
            manual_steps,
            log_path: r"C:\ProgramData\OSWorld\logs\rollback.log".to_string(),
        })
    }
    #[cfg(not(windows))]
    {
        let _ = confirmation;
        Err(InstallerError::SystemCheckFailed(
            "rollback_staging is only supported on Windows".to_string()
        ))
    }
}

// ==================== Main Function ====================

fn main() {
    tauri::Builder::default()
        .manage(AppState::new())
        .invoke_handler(tauri::generate_handler![
            set_install_type,
            get_config,
            save_config_to_json,
            detect_system_info,
            get_available_disks,
            set_user_config,
            start_installation,
            cancel_installation,
            calculate_estimated_time,
            prepare_staging,
            download_and_stage_iso,
            download_iso,
            write_config,
            install_refind,
            reboot_to_installer,
            cleanup_staging,
            rollback_staging,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
