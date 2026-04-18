# Quick Start Guide

## Prerequisites

1. **Install Rust** (if not already installed):
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   source ~/.cargo/env
   ```

2. **Install Node.js** (v18+ recommended):
   - Download from [nodejs.org](https://nodejs.org/)
   - Or use a version manager like `nvm`

## Setup

1. **Navigate to the project directory**:
   ```bash
   cd osworld-installer
   ```

2. **Install Node dependencies**:
   ```bash
   npm install
   ```

3. **Install Tauri CLI** (optional but recommended):
   ```bash
   cargo install tauri-cli --version "^2.0.0-beta"
   ```

## Development

Run the development server with hot reloading:

```bash
npm run tauri dev
```

This will:
- Start the Vite dev server on port 1420
- Launch the Tauri application window
- Enable hot reloading for both frontend and backend

## Building

Create a production build:

```bash
npm run tauri build
```

The built application will be in `src-tauri/target/release/`.

## Project Overview

### Windows
1. **Welcome** - Choose Dual Boot or Replace Windows
2. **System Check** - Verify system compatibility
3. **Disk Selection** - Select disk and partition size (Dual Boot only)
4. **User Setup** - Create user account
5. **Edition Selection** - Choose edition (Home/Gaming/Create)
6. **Installation Progress** - Monitor installation

### Key Files
- `src/App.tsx` - Main application with window navigation
- `src-tauri/src/main.rs` - Rust backend with all commands
- `src/lib/tauri.ts` - Frontend API for calling Rust commands
- `src/types/index.ts` - TypeScript type definitions

## Troubleshooting

### Port already in use
If port 1420 is in use, Vite will automatically try the next available port. Update `tauri.conf.json` if needed.

### Rust compilation errors
Make sure you have the latest Rust version:
```bash
rustup update
```

### Node modules issues
If you encounter issues with node_modules:
```bash
rm -rf node_modules package-lock.json
npm install
```

## Next Steps

1. Customize the system detection in `src-tauri/src/main.rs` to use actual Windows APIs
2. Implement real disk operations using WMI
3. Add actual Linux installation logic
4. Customize the styling in `src/styles/index.css`
5. Add more editions or features as needed
