import { useState, useEffect } from 'react';
import {
  Trash2,
  AlertTriangle,
  HardDrive,
  Shield,
  CheckCircle,
  XCircle,
  RotateCcw,
  Power,
  ArrowLeft,
  Loader2,
  FolderOpen,
  Check,
  Circle
} from 'lucide-react';
import {
  detectAltosInstallation,
  removeAltosPartitions,
  restoreWindowsBootloader,
  removeRefindFiles,
} from '../lib/tauri';

interface UninstallStep {
  id: string;
  name: string;
  status: 'pending' | 'in-progress' | 'completed' | 'error';
  message?: string;
}

interface UninstallerWindowProps {
  onBack?: () => void;
}

export default function UninstallerWindow({ onBack }: UninstallerWindowProps) {
  const [hasAltos, setHasAltos] = useState<boolean | null>(null);
  const [isChecking, setIsChecking] = useState(true);
  const [confirmation, setConfirmation] = useState('');
  const [expandCDrive, setExpandCDrive] = useState(true);
  const [isRemoving, setIsRemoving] = useState(false);
  const [isCompleted, setIsCompleted] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [steps, setSteps] = useState<UninstallStep[]>([
    { id: 'partitions', name: 'Remove AltOS partitions', status: 'pending' },
    { id: 'bootloader', name: 'Restore Windows bootloader', status: 'pending' },
    { id: 'refind', name: 'Remove rEFInd files', status: 'pending' },
  ]);

  useEffect(() => {
    checkInstallation();
  }, []);

  const checkInstallation = async () => {
    setIsChecking(true);
    try {
      const detected = await detectAltosInstallation();
      setHasAltos(detected);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to detect installation');
      setHasAltos(false);
    } finally {
      setIsChecking(false);
    }
  };

  const updateStep = (stepId: string, status: UninstallStep['status'], message?: string) => {
    setSteps(prev => prev.map(s => s.id === stepId ? { ...s, status, message } : s));
  };

  const handleRemove = async () => {
    if (confirmation !== 'REMOVE') return;

    setIsRemoving(true);
    setError(null);

    try {
      // Step 1: Remove partitions
      updateStep('partitions', 'in-progress');
      const partitionResult = await removeAltosPartitions('REMOVE', expandCDrive);
      updateStep('partitions', 'completed', partitionResult.join('; '));

      // Step 2: Restore Windows bootloader
      updateStep('bootloader', 'in-progress');
      const bootloaderResult = await restoreWindowsBootloader();
      updateStep('bootloader', 'completed', bootloaderResult);

      // Step 3: Remove rEFInd files
      updateStep('refind', 'in-progress');
      const refindResult = await removeRefindFiles();
      updateStep('refind', 'completed', refindResult);

      setIsCompleted(true);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Uninstall failed';
      setError(message);
      // Mark current in-progress step as error
      setSteps(prev => prev.map(s =>
        s.status === 'in-progress' ? { ...s, status: 'error', message } : s
      ));
    } finally {
      setIsRemoving(false);
    }
  };

  const handleRestart = () => {
    window.location.reload();
  };

  if (isChecking) {
    return (
      <div className="flex flex-col items-center justify-center py-12 space-y-4">
        <Loader2 className="w-8 h-8 text-altos-blue animate-spin" />
        <p className="text-altos-text-secondary text-sm">Detecting AltOS installation...</p>
      </div>
    );
  }

  if (hasAltos === false) {
    return (
      <div className="space-y-6">
        <div className="text-center space-y-1">
          <h2 className="text-xl font-semibold text-altos-text">Remove AltOS</h2>
          <p className="text-sm text-altos-text-secondary">
            No AltOS installation detected on this system.
          </p>
        </div>

        <div className="border-l-4 border-altos-success bg-altos-success/5 rounded-r-lg p-5">
          <div className="flex items-start gap-3">
            <CheckCircle className="w-6 h-6 text-altos-success flex-shrink-0" />
            <div>
              <h4 className="font-medium text-altos-text mb-1">Nothing to remove</h4>
              <p className="text-sm text-altos-text-secondary">
                We could not find any AltOS partitions, bootloader entries, or rEFInd files on this computer.
              </p>
            </div>
          </div>
        </div>

        <div className="flex justify-center pt-2">
          <button
            onClick={onBack}
            className="flex items-center gap-2 px-5 py-2.5 rounded-lg font-medium text-altos-text-secondary
              hover:text-altos-text hover:bg-[#1a1d21] transition-colors duration-150"
          >
            <ArrowLeft className="w-5 h-5" />
            <span>Back</span>
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="text-center space-y-1">
        <h2 className="text-xl font-semibold text-altos-text">Remove AltOS</h2>
        <p className="text-sm text-altos-text-secondary">
          Remove AltOS and restore Windows
        </p>
      </div>

      {/* Warning Banner */}
      {!isCompleted && (
        <div className="border-l-4 border-altos-danger bg-altos-danger/5 rounded-r-lg p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-altos-danger flex-shrink-0 mt-0.5" />
            <div>
              <h4 className="font-medium text-altos-text text-sm mb-1">Warning</h4>
              <p className="text-sm text-altos-text-secondary">
                This will remove AltOS. Your Windows files will not be affected.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* What will be deleted / kept */}
      {!isCompleted && !isRemoving && (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="bg-[#1a1d21] border border-altos-border rounded-xl p-4">
            <h4 className="text-sm font-medium text-altos-danger mb-3 flex items-center gap-2">
              <Trash2 className="w-4 h-4" />
              Will be deleted
            </h4>
            <ul className="space-y-2">
              <li className="flex items-center gap-2 text-sm text-altos-text-secondary">
                <XCircle className="w-4 h-4 text-altos-danger flex-shrink-0" />
                Linux partitions (OSWORLDBOOT, root, home)
              </li>
              <li className="flex items-center gap-2 text-sm text-altos-text-secondary">
                <XCircle className="w-4 h-4 text-altos-danger flex-shrink-0" />
                GRUB bootloader entries
              </li>
              <li className="flex items-center gap-2 text-sm text-altos-text-secondary">
                <XCircle className="w-4 h-4 text-altos-danger flex-shrink-0" />
                AltOS files and rEFInd
              </li>
            </ul>
          </div>

          <div className="bg-[#1a1d21] border border-altos-border rounded-xl p-4">
            <h4 className="text-sm font-medium text-altos-success mb-3 flex items-center gap-2">
              <Shield className="w-4 h-4" />
              Will be kept
            </h4>
            <ul className="space-y-2">
              <li className="flex items-center gap-2 text-sm text-altos-text-secondary">
                <CheckCircle className="w-4 h-4 text-altos-success flex-shrink-0" />
                Windows partition (untouched)
              </li>
              <li className="flex items-center gap-2 text-sm text-altos-text-secondary">
                <CheckCircle className="w-4 h-4 text-altos-success flex-shrink-0" />
                Personal files and documents
              </li>
              <li className="flex items-center gap-2 text-sm text-altos-text-secondary">
                <CheckCircle className="w-4 h-4 text-altos-success flex-shrink-0" />
                Installed Windows applications
              </li>
            </ul>
          </div>
        </div>
      )}

      {/* Expand C: drive option */}
      {!isCompleted && !isRemoving && (
        <div className="flex items-center gap-3 bg-[#1a1d21] border border-altos-border rounded-xl p-4">
          <HardDrive className="w-5 h-5 text-altos-blue flex-shrink-0" />
          <div className="flex-1">
            <p className="text-sm font-medium text-altos-text">Expand C: drive</p>
            <p className="text-xs text-altos-text-secondary">
              Reclaim the space used by AltOS partitions and add it back to C:
            </p>
          </div>
          <label className="relative inline-flex items-center cursor-pointer">
            <input
              type="checkbox"
              checked={expandCDrive}
              onChange={(e) => setExpandCDrive(e.target.checked)}
              className="sr-only peer"
            />
            <div className="w-11 h-6 bg-[#1e2127] peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-altos-blue" />
          </label>
        </div>
      )}

      {/* Progress Steps */}
      {(isRemoving || isCompleted || steps.some(s => s.status !== 'pending')) && (
        <div className="bg-[#1a1d21] border border-altos-border rounded-xl p-4 space-y-3">
          {steps.map((step) => (
            <div key={step.id} className="flex items-center gap-3">
              <div className={`
                w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0
                ${step.status === 'completed' ? 'bg-altos-success text-white' :
                  step.status === 'in-progress' ? 'bg-altos-blue text-white' :
                  step.status === 'error' ? 'bg-altos-danger text-white' :
                  'bg-[#1e2127] text-altos-text-secondary'}
              `}>
                {step.status === 'completed' ? <Check className="w-4 h-4" /> :
                 step.status === 'in-progress' ? <Loader2 className="w-4 h-4 animate-spin" /> :
                 step.status === 'error' ? <AlertTriangle className="w-4 h-4" /> :
                 <Circle className="w-4 h-4" />}
              </div>
              <div className="flex-1">
                <p className={`text-sm font-medium ${
                  step.status === 'completed' ? 'text-altos-success' :
                  step.status === 'in-progress' ? 'text-altos-blue' :
                  step.status === 'error' ? 'text-altos-danger' :
                  'text-altos-text-secondary'
                }`}>
                  {step.name}
                </p>
                {step.message && (
                  <p className="text-xs text-altos-text-secondary mt-0.5">{step.message}</p>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Error */}
      {error && (
        <div className="border-l-4 border-altos-danger bg-[#1a1d21] rounded-r-lg p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-altos-danger flex-shrink-0 mt-0.5" />
            <div>
              <h4 className="font-medium text-altos-text text-sm mb-1">Uninstall Failed</h4>
              <p className="text-sm text-altos-text-secondary">{error}</p>
            </div>
          </div>
        </div>
      )}

      {/* Completed */}
      {isCompleted && (
        <div className="border-l-4 border-altos-success bg-altos-success/5 rounded-r-lg p-5">
          <div className="flex items-start gap-3">
            <CheckCircle className="w-6 h-6 text-altos-success flex-shrink-0" />
            <div>
              <h4 className="font-medium text-altos-text mb-1">AltOS has been removed</h4>
              <p className="text-sm text-altos-text-secondary">
                Your PC will restart into Windows.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Confirmation Input */}
      {!isCompleted && !isRemoving && (
        <div className="bg-[#1a1d21] border border-altos-border rounded-xl p-4">
          <label className="block text-sm font-medium text-altos-text mb-2">
            Type <span className="text-altos-danger font-bold">REMOVE</span> to confirm
          </label>
          <input
            type="text"
            value={confirmation}
            onChange={(e) => setConfirmation(e.target.value)}
            placeholder="REMOVE"
            className="w-full bg-altos-card border border-altos-border rounded-lg px-4 py-2.5 text-altos-text text-sm
              placeholder:text-altos-text-secondary/50 focus:outline-none focus:border-altos-blue transition-colors"
          />
        </div>
      )}

      {/* Action Buttons */}
      <div className="flex justify-between pt-2">
        {!isCompleted && !isRemoving && (
          <>
            <button
              onClick={onBack}
              className="flex items-center gap-2 px-5 py-2.5 rounded-lg font-medium text-altos-text-secondary
                hover:text-altos-text hover:bg-[#1a1d21] transition-colors duration-150"
            >
              <ArrowLeft className="w-5 h-5" />
              <span>Cancel</span>
            </button>

            <button
              onClick={handleRemove}
              disabled={confirmation !== 'REMOVE' || isRemoving}
              className={`
                flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white
                transition-colors duration-150
                ${confirmation === 'REMOVE' && !isRemoving
                  ? 'bg-altos-danger hover:bg-red-600'
                  : 'bg-[#3a3f47] cursor-not-allowed text-altos-text-secondary'
                }
              `}
            >
              <Trash2 className="w-5 h-5" />
              <span>Remove AltOS</span>
            </button>
          </>
        )}

        {isCompleted && (
          <div className="flex justify-center gap-3 w-full">
            <button
              onClick={() => {
                // Restart the computer
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                (window as any).__TAURI__?.core?.invoke?.('reboot_to_installer')?.catch(() => {
                  // If reboot fails, just show a message
                });
              }}
              className="flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white
                bg-altos-blue hover:bg-altos-blue-hover transition-colors duration-150"
            >
              <Power className="w-5 h-5" />
              <span>Restart Now</span>
            </button>
            <button
              onClick={handleRestart}
              className="flex items-center gap-2 px-5 py-2.5 rounded-lg font-medium text-altos-text-secondary
                bg-[#1a1d21] hover:text-altos-text border border-altos-border hover:border-[#3a3f47] transition-colors duration-150"
            >
              <FolderOpen className="w-5 h-5" />
              <span>Close</span>
            </button>
          </div>
        )}

        {error && !isRemoving && (
          <div className="flex justify-center gap-3 w-full">
            <button
              onClick={handleRestart}
              className="flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white
                bg-altos-blue hover:bg-altos-blue-hover transition-colors duration-150"
            >
              <RotateCcw className="w-5 h-5" />
              <span>Try Again</span>
            </button>
          </div>
        )}
      </div>
    </div>
  );
}


