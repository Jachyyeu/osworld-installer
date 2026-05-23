import type { SystemInfo, PcManufacturerInfo, DiskInfo, InstallConfig } from '../../types';

export const mockSystemInfo: SystemInfo = {
  windows_version: 'Windows 11 Pro (23H2)',
  disk_free_space_gb: 250,
  ram_gb: 16,
  cpu_info: 'Intel Core i7-13700H',
  secure_boot_enabled: false,
  bitlocker_enabled: false,
};

export const mockSystemInfoWithSecureBoot: SystemInfo = {
  windows_version: 'Windows 11 Pro (23H2)',
  disk_free_space_gb: 250,
  ram_gb: 16,
  cpu_info: 'Intel Core i7-13700H',
  secure_boot_enabled: true,
  secure_boot_strategy: 'mok_enrollment',
  bitlocker_enabled: false,
};

export const mockManufacturerDell: PcManufacturerInfo = {
  manufacturer: 'Dell Inc.',
  boot_menu_key: 'F12',
  bios_key: 'F2',
};

export const mockDisks: DiskInfo[] = [
  {
    name: 'C: Drive',
    size_gb: 512,
    free_space_gb: 250,
  },
  {
    name: 'D: Drive',
    size_gb: 1024,
    free_space_gb: 800,
  },
];

export const mockConfigComplete: InstallConfig = {
  install_type: 'dualboot',
  windows_version: 'Windows 11 Pro (23H2)',
  disk_free_space_gb: 250,
  ram_gb: 16,
  cpu_info: 'Intel Core i7-13700H',
  secure_boot_enabled: false,
  secure_boot_strategy: 'mok_enrollment',
  bitlocker_enabled: false,
  selected_disk: 'D: Drive',
  linux_size_gb: 240,
  filesystem: 'ext4',
  encrypt: true,
  luks_password: 'secret123',
  username: 'user',
  computer_name: 'altos-pc',
  password: 'password123',
};
