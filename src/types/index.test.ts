import type { InstallConfig } from './index';

// This file verifies that InstallConfig accepts all optional fields.
// If it compiles, the types are correct.
const _typeCheck: InstallConfig = {
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

// Dummy test so vitest doesn't complain about an empty suite
describe('types', () => {
  it('compile-time type check passes', () => {
    expect(_typeCheck).toBeDefined();
  });
});
