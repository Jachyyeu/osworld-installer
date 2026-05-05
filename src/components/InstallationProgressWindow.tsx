import { useState, useEffect, useRef } from 'react';
import {
  Download,
  HardDrive,
  Cog,
  CheckCircle,
  X,
  AlertTriangle,
  RotateCcw,
  Check,
  Power,
  Circle
} from 'lucide-react';
import {
  prepareStaging,
  downloadAndStageIso,
  installRefind,
  rebootToInstaller,
  onDownloadProgress,
  getConfig,
  cancelInstallation,
  rollbackStaging
} from '../lib/tauri';
import type { StagingInfo } from '../types';

interface InstallStep {
  id: string;
  name: string;
  description: string;
  icon: React.ReactNode;
  status: 'pending' | 'in-progress' | 'completed' | 'error';
}

const INSTALL_STEPS: InstallStep[] = [
  { id: 'prepare', name: 'Prepare Disk', description: 'Allocating disk space...', icon: <HardDrive className="w-5 h-5" />, status: 'pending' },
  { id: 'download', name: 'Download OS', description: 'Downloading Arch Linux ISO...', icon: <Download className="w-5 h-5" />, status: 'pending' },
  { id: 'bootloader', name: 'Bootloader', description: 'Setting up rEFInd...', icon: <Cog className="w-5 h-5" />, status: 'pending' },
  { id: 'reboot', name: 'Ready to Reboot', description: 'All set! Reboot to continue.', icon: <CheckCircle className="w-5 h-5" />, status: 'pending' },
];

interface RollbackAction {
  description: string;
  success: boolean;
  warning?: string;
}

interface RollbackStatus {
  success: boolean;
  actions: RollbackAction[];
  manual_steps: string[];
  log_path: string;
}

export default function InstallationProgressWindow() {
  const [steps, setSteps] = useState<InstallStep[]>(INSTALL_STEPS);
  const [overallProgress, setOverallProgress] = useState(0);
  const [currentStepName, setCurrentStepName] = useState('Starting installation...');
  const [isInstalling, setIsInstalling] = useState(true);
  const [isCompleted, setIsCompleted] = useState(false);
  const [showCancelDialog, setShowCancelDialog] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [downloadPercent, setDownloadPercent] = useState(0);
  const [isRollingBack, setIsRollingBack] = useState(false);
  const [rollbackStatus, setRollbackStatus] = useState<RollbackStatus | null>(null);
  const unlistenRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    runInstallationStages();
    setupDownloadListener();

    return () => {
      if (unlistenRef.current) {
        unlistenRef.current();
      }
    };
  }, []);

  const setupDownloadListener = async () => {
    try {
      const unlisten = await onDownloadProgress((progress) => {
        setDownloadPercent(progress.percent);
        setOverallProgress(25 + Math.floor(progress.percent * 0.4));
      });
      unlistenRef.current = unlisten;
    } catch (err) {
      console.error('Failed to listen to download progress:', err);
    }
  };

  const runInstallationStages = async () => {
    try {
      const config = await getConfig();

      if (!config.linux_size_gb) {
        throw new Error('Linux partition size not configured');
      }

      // Stage 1: Prepare staging
      updateStepStatus('prepare', 'in-progress');
      setCurrentStepName('Preparing disk space...');
      setOverallProgress(5);

      const stagingInfo: StagingInfo = await prepareStaging(config, 'OSWORLD');

      updateStepStatus('prepare', 'completed');

      // Stage 2: Download ISO
      updateStepStatus('download', 'in-progress');
      setCurrentStepName('Downloading Arch Linux ISO...');
      setOverallProgress(25);

      await downloadAndStageIso(stagingInfo.boot_partition_letter, config);

      updateStepStatus('download', 'completed');

      // Stage 3: Install rEFInd
      updateStepStatus('bootloader', 'in-progress');
      setCurrentStepName('Setting up bootloader...');
      setOverallProgress(75);

      await installRefind();

      updateStepStatus('bootloader', 'completed');
      updateStepStatus('reboot', 'completed');
      setOverallProgress(100);
      setIsCompleted(true);
      setIsInstalling(false);
      setCurrentStepName('Ready to reboot into AltOS Installer');
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Installation failed';
      setError(message);
      setIsInstalling(false);

      // Mark current step as error
      setSteps(prev => prev.map(step =>
        step.status === 'in-progress' ? { ...step, status: 'error' } : step
      ));

      // Auto-rollback
      setIsRollingBack(true);
      setCurrentStepName('Rolling back changes...');
      try {
        const status = await rollbackStaging('ROLLBACK');
        setRollbackStatus(status);
        setIsRollingBack(false);
      } catch (rollbackErr) {
        setIsRollingBack(false);
        setRollbackStatus({
          success: false,
          actions: [],
          manual_steps: ['Rollback failed. You may need to run Disk Management to clean up leftover partitions.'],
          log_path: 'C:\\ProgramData\\OSWorld\\logs\\rollback.log'
        });
      }
    }
  };

  const updateStepStatus = (stepId: string, status: InstallStep['status']) => {
    setSteps(prev => prev.map(step =>
      step.id === stepId ? { ...step, status } : step
    ));
  };

  const handleCancel = async () => {
    try {
      await cancelInstallation();
      setShowCancelDialog(false);
      setIsInstalling(false);
      setError('Installation was cancelled by user');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to cancel installation');
    }
  };

  const handleRestart = () => {
    window.location.reload();
  };

  const handleReboot = async () => {
    try {
      await rebootToInstaller();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to initiate reboot');
    }
  };

  if (showCancelDialog) {
    return (
      <div className="space-y-6">
        <div className="border-l-4 border-altos-warning bg-[#1a1d21] rounded-r-lg p-6">
          <div className="flex items-start gap-4">
            <div className="w-10 h-10 bg-altos-warning/10 rounded-full flex items-center justify-center flex-shrink-0">
              <AlertTriangle className="w-5 h-5 text-altos-warning" />
            </div>
            <div className="flex-1">
              <h3 className="text-base font-semibold text-altos-text mb-2">
                Cancel Installation?
              </h3>
              <p className="text-sm text-altos-text-secondary mb-5">
                Cancelling may leave your system in an inconsistent state.
                We recommend letting the installation complete.
              </p>
              <div className="flex gap-3">
                <button
                  onClick={() => setShowCancelDialog(false)}
                  className="px-4 py-2 bg-altos-card border border-altos-border rounded-lg text-altos-text font-medium hover:bg-[#1a1d21] transition-colors duration-150"
                >
                  Continue Installation
                </button>
                <button
                  onClick={handleCancel}
                  className="px-4 py-2 bg-altos-danger text-white rounded-lg font-medium hover:opacity-90 transition-opacity duration-150"
                >
                  Yes, Cancel
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="text-center space-y-1">
        <h2 className="text-xl font-semibold text-altos-text">
          {isCompleted ? 'Ready to Reboot' : 'Installing AltOS'}
        </h2>
        <p className="text-sm text-altos-text-secondary">
          {isCompleted
            ? 'All files are staged. Reboot to start the AltOS Installer.'
            : 'Please do not turn off your computer during installation.'
          }
        </p>
      </div>

      {/* Rollback in Progress */}
      {isRollingBack && (
        <div className="border-l-4 border-altos-blue bg-[#1a1d21] rounded-r-lg p-5">
          <div className="flex items-center gap-3 mb-2">
            <svg className="animate-spin h-5 w-5 text-altos-blue" viewBox="0 0 24 24">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
            </svg>
            <h4 className="font-medium text-altos-text">Rolling back changes...</h4>
          </div>
          <p className="text-sm text-altos-text-secondary">
            Your system is being restored to its original state. Please wait.
          </p>
        </div>
      )}

      {/* Error Message */}
      {error && !isRollingBack && (
        <div className="border-l-4 border-altos-danger bg-[#1a1d21] rounded-r-lg p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-altos-danger flex-shrink-0 mt-0.5" />
            <div>
              <h4 className="font-medium text-altos-text text-sm mb-1">Installation Failed</h4>
              <p className="text-sm text-altos-text-secondary">{error}</p>
            </div>
          </div>
        </div>
      )}

      {/* Rollback Complete */}
      {rollbackStatus && !isRollingBack && (
        <div className={`border-l-4 rounded-r-lg p-5 ${rollbackStatus.success ? 'border-altos-success bg-altos-success/5' : 'border-altos-warning bg-altos-warning/5'}`}>
          <div className="flex items-start gap-3 mb-4">
            {rollbackStatus.success ? (
              <CheckCircle className="w-6 h-6 text-altos-success flex-shrink-0" />
            ) : (
              <AlertTriangle className="w-6 h-6 text-altos-warning flex-shrink-0" />
            )}
            <div>
              <h4 className="font-medium text-altos-text mb-1">
                {rollbackStatus.success ? 'Your system has been restored' : 'Rollback completed with warnings'}
              </h4>
              <p className="text-sm text-altos-text-secondary">
                {rollbackStatus.success
                  ? 'No changes were made to your system. You can try again safely.'
                  : 'Some items could not be rolled back automatically. See below for manual steps.'}
              </p>
            </div>
          </div>

          {/* Rollback Actions */}
          {rollbackStatus.actions.length > 0 && (
            <div className="space-y-2 mb-4">
              <h5 className="text-sm font-medium text-altos-text">Actions taken:</h5>
              {rollbackStatus.actions.map((action, idx) => (
                <div key={idx} className={`text-sm p-2.5 rounded-lg ${action.success ? 'bg-altos-success/10 text-altos-success' : 'bg-altos-danger/10 text-altos-danger'}`}>
                  <div className="flex items-start gap-2">
                    <span className="flex-shrink-0 mt-0.5">{action.success ? '✓' : '✗'}</span>
                    <span>{action.description}</span>
                  </div>
                  {action.warning && (
                    <p className="text-xs mt-1 text-altos-warning ml-4">{action.warning}</p>
                  )}
                </div>
              ))}
            </div>
          )}

          {/* Manual Steps */}
          {rollbackStatus.manual_steps.length > 0 && (
            <div className="bg-altos-card border border-altos-border rounded-lg p-4">
              <h5 className="text-sm font-medium text-altos-text mb-2">Manual steps needed:</h5>
              <ul className="text-sm text-altos-text-secondary space-y-1">
                {rollbackStatus.manual_steps.map((step, idx) => (
                  <li key={idx} className="flex items-start gap-2">
                    <span className="text-altos-text-secondary mt-0.5">•</span>
                    <span>{step}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}

          <p className="text-xs text-altos-text-secondary mt-3">
            Log saved to: {rollbackStatus.log_path}
          </p>
        </div>
      )}

      {/* Progress Section */}
      {!error && !isRollingBack && !rollbackStatus && (
        <div className="space-y-6">
          {/* Overall Progress */}
          <div className="bg-[#1a1d21] border border-altos-border rounded-xl p-5">
            <div className="flex items-center justify-between mb-3">
              <span className="font-medium text-altos-text text-sm">Overall Progress</span>
              <span className="text-xl font-semibold text-altos-blue">{overallProgress}%</span>
            </div>

            {/* Progress Bar */}
            <div className="h-2.5 bg-[#1e2127] rounded-full overflow-hidden">
              <div
                className={`
                  h-full rounded-full transition-all duration-500
                  ${isCompleted ? 'bg-altos-success' : 'bg-altos-blue animate-progress-pulse'}
                `}
                style={{ width: `${overallProgress}%` }}
              />
            </div>

            {/* Download sub-progress */}
            {steps[1]?.status === 'in-progress' && downloadPercent > 0 && (
              <div className="mt-4">
                <div className="flex items-center justify-between mb-1.5">
                  <span className="text-xs text-altos-text-secondary">ISO Download</span>
                  <span className="text-xs font-medium text-altos-text">{downloadPercent}%</span>
                </div>
                <div className="h-1.5 bg-[#1e2127] rounded-full overflow-hidden">
                  <div
                    className="h-full bg-altos-blue rounded-full transition-all duration-300"
                    style={{ width: `${downloadPercent}%` }}
                  />
                </div>
              </div>
            )}

            {/* Current Step */}
            <div className="mt-4 flex items-center gap-3">
              {!isCompleted && isInstalling && (
                <svg className="animate-spin h-5 w-5 text-altos-blue" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                </svg>
              )}
              {isCompleted && <CheckCircle className="w-5 h-5 text-altos-success" />}
              <span className="text-altos-text text-sm font-medium">{currentStepName}</span>
            </div>
          </div>

          {/* Steps Timeline */}
          <div className="space-y-0">
            {steps.map((step, index) => (
              <div
                key={step.id}
                className="flex gap-4"
              >
                {/* Timeline line and dot */}
                <div className="flex flex-col items-center">
                  <div className={`
                    w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0 transition-colors duration-150
                    ${step.status === 'completed'
                      ? 'bg-altos-success text-white'
                      : step.status === 'in-progress'
                        ? 'bg-altos-blue text-white'
                        : step.status === 'error'
                          ? 'bg-altos-danger text-white'
                          : 'bg-[#1e2127] text-altos-text-secondary'
                    }
                  `}>
                    {step.status === 'completed' ? (
                      <Check className="w-4 h-4" />
                    ) : step.status === 'error' ? (
                      <AlertTriangle className="w-4 h-4" />
                    ) : (
                      step.icon
                    )}
                  </div>
                  {index < steps.length - 1 && (
                    <div className={`
                      w-0.5 flex-1 min-h-[24px] my-1 transition-colors duration-150
                      ${step.status === 'completed' ? 'bg-altos-success' : 'bg-[#1e2127]'}
                    `} />
                  )}
                </div>

                {/* Step content */}
                <div className={`
                  flex-1 pb-5 pt-1 transition-colors duration-150
                  ${index === steps.length - 1 ? '' : ''}
                `}>
                  <p className={`
                    font-medium text-sm
                    ${step.status === 'completed'
                      ? 'text-altos-success'
                      : step.status === 'in-progress'
                        ? 'text-altos-blue'
                        : step.status === 'error'
                          ? 'text-altos-danger'
                          : 'text-altos-text-secondary'
                    }
                  `}>
                    {step.name}
                  </p>
                  <p className="text-xs text-altos-text-secondary mt-0.5">{step.description}</p>

                  {/* Status indicator */}
                  <div className="mt-1.5">
                    {step.status === 'in-progress' && (
                      <span className="inline-flex items-center gap-1.5 text-xs text-altos-blue">
                        <svg className="animate-spin h-3 w-3" viewBox="0 0 24 24">
                          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                        </svg>
                        In progress...
                      </span>
                    )}
                    {step.status === 'completed' && (
                      <span className="inline-flex items-center gap-1.5 text-xs text-altos-success">
                        <CheckCircle className="w-3 h-3" />
                        Completed
                      </span>
                    )}
                    {step.status === 'error' && (
                      <span className="inline-flex items-center gap-1.5 text-xs text-altos-danger">
                        <AlertTriangle className="w-3 h-3" />
                        Failed
                      </span>
                    )}
                    {step.status === 'pending' && (
                      <span className="inline-flex items-center gap-1.5 text-xs text-altos-text-secondary">
                        <Circle className="w-3 h-3" />
                        Waiting...
                      </span>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Action Buttons */}
      <div className="flex justify-center gap-3 pt-2">
        {isInstalling && !isCompleted && (
          <button
            onClick={() => setShowCancelDialog(true)}
            className="flex items-center gap-2 px-5 py-2.5 rounded-lg font-medium text-altos-danger
              bg-altos-danger/10 hover:bg-altos-danger/20 transition-colors duration-150"
          >
            <X className="w-5 h-5" />
            <span>Cancel</span>
          </button>
        )}

        {error && !rollbackStatus && (
          <button
            onClick={handleRestart}
            className="flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white
              bg-altos-blue hover:bg-altos-blue-hover transition-colors duration-150"
          >
            <RotateCcw className="w-5 h-5" />
            <span>Restart Installer</span>
          </button>
        )}

        {rollbackStatus && !isRollingBack && (
          <>
            <button
              onClick={handleRestart}
              className="flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white
                bg-altos-blue hover:bg-altos-blue-hover transition-colors duration-150"
            >
              <RotateCcw className="w-5 h-5" />
              <span>Try Again</span>
            </button>
            <button
              onClick={() => window.open('https://github.com/osworld-installer/support', '_blank')}
              className="flex items-center gap-2 px-5 py-2.5 rounded-lg font-medium text-altos-text-secondary
                bg-[#1a1d21] hover:text-altos-text border border-altos-border hover:border-[#3a3f47] transition-colors duration-150"
            >
              <AlertTriangle className="w-5 h-5" />
              <span>Get Help</span>
            </button>
          </>
        )}

        {isCompleted && (
          <button
            onClick={handleReboot}
            className="flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white
              bg-altos-success hover:opacity-90 transition-opacity duration-150"
          >
            <Power className="w-5 h-5" />
            <span>Reboot to Installer</span>
          </button>
        )}
      </div>

      {/* Tips */}
      {!isCompleted && !error && (
        <div className="bg-[#1a1d21] border border-altos-border rounded-lg p-4">
          <div className="flex items-start gap-3">
            <div className="w-7 h-7 bg-altos-blue/10 rounded-full flex items-center justify-center flex-shrink-0">
              <span className="text-altos-blue font-bold text-xs">?</span>
            </div>
            <div>
              <h4 className="font-medium text-altos-text text-sm mb-1">Installation Tips</h4>
              <ul className="text-sm text-altos-text-secondary space-y-1">
                <li>• Keep your computer plugged in during installation</li>
                <li>• The staging process may take 10-20 minutes depending on your connection</li>
                <li>• Your computer will restart into the AltOS Installer when ready</li>
              </ul>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
