# OSWorld Installer

A modern Linux distribution installer built with **Tauri v2 Beta** and **React + TypeScript**.

## Features

- **Welcome Screen**: Choose between Dual Boot (keep Windows) or Replace Windows
- **System Check**: Detects Windows version, disk space, RAM, CPU, Secure Boot, and BitLocker status
- **Disk Selection**: Interactive disk selection with size slider (Dual Boot only)
- **User Setup**: Form validation for username, computer name, and password
- **Edition Selection**: Choose from Home (Free), Gaming ($9.99), or Create ($14.99)
- **Installation Progress**: Real-time progress tracking with cancel option

## Tech Stack

- **Backend**: Rust with Tauri v2 Beta
- **Frontend**: React 18 + TypeScript
- **Styling**: Tailwind CSS
- **Icons**: Lucide React

## Project Structure

```
osworld-installer/
├── src/                          # React frontend
│   ├── components/               # Window components
│   │   ├── WelcomeWindow.tsx     # Window 1: Welcome
│   │   ├── SystemCheckWindow.tsx # Window 2: System Check
│   │   ├── DiskSelectionWindow.tsx # Window 3: Disk Selection
│   │   ├── UserSetupWindow.tsx   # Window 4: User Setup
│   │   ├── EditionSelectionWindow.tsx # Window 5: Edition Selection
│   │   └── InstallationProgressWindow.tsx # Window 6: Installation Progress
│   ├── lib/
│   │   └── tauri.ts              # Tauri API helpers
│   ├── types/
│   │   └── index.ts              # TypeScript types
│   ├── styles/
│   │   └── index.css             # Tailwind styles
│   ├── App.tsx                   # Main app with navigation
│   └── main.tsx                  # React entry point
├── src-tauri/                    # Rust backend
│   ├── src/
│   │   └── main.rs               # Main Rust code with commands
│   ├── icons/                    # App icons
│   ├── Cargo.toml                # Rust dependencies
│   ├── tauri.conf.json           # Tauri configuration
│   └── build.rs                  # Build script
├── package.json                  # Node dependencies
├── vite.config.ts                # Vite configuration
├── tailwind.config.js            # Tailwind configuration
└── tsconfig.json                 # TypeScript configuration
```

## Prerequisites

- [Rust](https://rustup.rs/) (1.70+)
- [Node.js](https://nodejs.org/) (18+)
- Windows 10/11 (for full system detection features)

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd osworld-installer
```

2. Install Node dependencies:
```bash
npm install
```

3. Install Tauri CLI:
```bash
cargo install tauri-cli --version "^2.0.0-beta"
```

## Development

Run the development server:

```bash
npm run tauri dev
```

This will:
1. Start the Vite dev server on port 1420
2. Launch the Tauri application window
3. Enable hot reloading for both frontend and backend

## Building

Build the production application:

```bash
npm run tauri build
```

The built application will be in `src-tauri/target/release/`.

## Configuration

The installation configuration is stored in a serializable struct that can be saved to JSON:

```rust
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
    pub edition: Option<Edition>,
}
```

## Error Handling

All commands return `Result<T>` with proper error types:

```rust
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
```

## Tauri Commands

| Command | Description |
|---------|-------------|
| `set_install_type` | Set installation type (dualboot/replace) |
| `get_config` | Get current installation configuration |
| `save_config_to_json` | Save configuration to JSON file |
| `detect_system_info` | Detect system information |
| `get_available_disks` | Get list of available disks |
| `set_disk_config` | Set disk and partition size |
| `set_user_config` | Set user account details |
| `set_edition` | Set selected edition |
| `start_installation` | Start the installation process |
| `cancel_installation` | Cancel ongoing installation |
| `calculate_estimated_time` | Calculate estimated installation time |
| `verify_installation` | Verify staging completeness (partitions, ISO, config, rEFInd) |
| `detect_altos_installation` | Check if AltOS is installed on this system |
| `remove_altos_partitions` | Remove AltOS partitions and optionally expand C: |
| `restore_windows_bootloader` | Restore Windows Boot Manager as default |
| `remove_refind_files` | Remove rEFInd files from EFI partition |

## Uninstalling AltOS

To remove AltOS and restore your system to Windows-only:

1. Open the AltOS Installer app
2. Click **"Remove AltOS"** on the welcome screen
3. Review what will be deleted and what will be kept
4. Toggle **"Expand C: drive"** if you want to reclaim the space
5. Type `REMOVE` in the confirmation field
6. Click **"Remove AltOS"**

The uninstaller will:
- Delete the OSWORLDBOOT, Linux root, and Linux home partitions
- Remove rEFInd and GRUB bootloader entries
- Restore Windows Boot Manager as the default
- Optionally expand your C: drive to reclaim space

Your Windows files, personal documents, and installed applications will not be affected.

## License

MIT License - See LICENSE file for details.

## Contributing

Contributions are welcome! Please read CONTRIBUTING.md for guidelines.
