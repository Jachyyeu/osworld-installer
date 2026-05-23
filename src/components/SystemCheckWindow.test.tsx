import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor, act } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import SystemCheckWindow from './SystemCheckWindow';
import {
  mockSystemInfo,
  mockSystemInfoWithSecureBoot,
  mockManufacturerDell,
} from '../test/mocks/fixtures';

const mockDetectSystemInfo = vi.fn();
const mockDetectPcManufacturer = vi.fn();

vi.mock('../lib/tauri', () => ({
  detectSystemInfo: () => mockDetectSystemInfo(),
  detectPcManufacturer: () => mockDetectPcManufacturer(),
}));

describe('SystemCheckWindow', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockDetectSystemInfo.mockResolvedValue(mockSystemInfo);
    mockDetectPcManufacturer.mockResolvedValue(mockManufacturerDell);
  });

  it('shows loading spinner initially', () => {
    mockDetectSystemInfo.mockImplementation(() => new Promise(() => {}));
    render(<SystemCheckWindow onNext={vi.fn()} onBack={vi.fn()} />);
    expect(screen.getByText(/Checking your system/i)).toBeInTheDocument();
  });

  it('shows success message after checks pass', async () => {
    render(<SystemCheckWindow onNext={vi.fn()} onBack={vi.fn()} />);

    await waitFor(() => {
      expect(screen.getByText(/Your PC is ready!/i)).toBeInTheDocument();
    });
  });

  it('shows green passed pills after success', async () => {
    render(<SystemCheckWindow onNext={vi.fn()} onBack={vi.fn()} />);

    await waitFor(() => {
      expect(screen.getByText(/checks passed/i)).toBeInTheDocument();
    });
  });

  it('shows error row with Fix button when Secure Boot is enabled', async () => {
    mockDetectSystemInfo.mockResolvedValue(mockSystemInfoWithSecureBoot);
    render(<SystemCheckWindow onNext={vi.fn()} onBack={vi.fn()} />);

    await waitFor(() => {
      expect(screen.getByText('Secure Boot')).toBeInTheDocument();
    });

    expect(screen.getByText('Enabled')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Fix/i })).toBeInTheDocument();
  });

  it('renders manufacturer badge in guidance modal', async () => {
    mockDetectSystemInfo.mockResolvedValue(mockSystemInfoWithSecureBoot);
    const user = userEvent.setup();
    render(<SystemCheckWindow onNext={vi.fn()} onBack={vi.fn()} />);

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /Fix/i })).toBeInTheDocument();
    });

    await act(async () => {
      await user.click(screen.getByRole('button', { name: /Fix/i }));
    });

    await waitFor(() => {
      expect(screen.getByText('Dell Inc.')).toBeInTheDocument();
    });
  });
});
