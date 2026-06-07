import { useState, useEffect, useRef, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Download,
  HardDrive,
  Cog,
  CheckCircle2,
  AlertTriangle,
  RotateCcw,
  Power,
  Check,
  Circle,
  ChevronDown,
  Clock,
  Terminal,
  Sparkles,
} from 'lucide-react';
import {
  prepareStaging,
  downloadAndStageIso,
  installRefind,
  rebootToInstaller,
  onDownloadProgress,
  getConfig,
  cancelInstallation,
  rollbackStaging,
  writeTestState,
} from '../lib/tauri';
import type { StagingInfo } from '../types';

const TEST_STATE_PATH = 'C:\\\\altos-test-state.json';

// ==================== Types ====================

interface InstallStep {
  id: string;
  name: string;
  description: string;
  icon: React.ReactNode;
  status: 'pending' | 'in-progress' | 'completed' | 'error';
}

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

interface LogEntry {
  time: string;
  message: string;
  type: 'info' | 'success' | 'error';
}

interface Phase {
  id: string;
  label: string;
  description: string;
  weight: number; // percentage weight out of 100
}

// ==================== Constants ====================

const PHASES: Phase[] = [
  {
    id: 'prepare',
    label: 'Preparing your disk…',
    description: 'Making room for AltOS alongside Windows',
    weight: 20,
  },
  {
    id: 'download',
    label: 'Downloading AltOS…',
    description: 'Grabbing the latest files — this takes about 5 minutes',
    weight: 40,
  },
  {
    id: 'verify',
    label: 'Verifying files…',
    description: 'Double-checking everything is correct',
    weight: 10,
  },
  {
    id: 'bootloader',
    label: 'Setting up the bootloader…',
    description: 'Teaching your PC how to start AltOS',
    weight: 20,
  },
  {
    id: 'finalize',
    label: 'Finalizing…',
    description: 'Almost there! Just a few finishing touches',
    weight: 10,
  },
];

const INSTALL_STEPS: InstallStep[] = [
  {
    id: 'prepare',
    name: 'Prepare Disk',
    description: 'Allocating disk space…',
    icon: <HardDrive className="w-5 h-5" />,
    status: 'pending',
  },
  {
    id: 'download',
    name: 'Download OS',
    description: 'Downloading Arch Linux ISO…',
    icon: <Download className="w-5 h-5" />,
    status: 'pending',
  },
  {
    id: 'bootloader',
    name: 'Bootloader',
    description: 'Setting up rEFInd…',
    icon: <Cog className="w-5 h-5" />,
    status: 'pending',
  },
  {
    id: 'reboot',
    name: 'Ready to Reboot',
    description: 'All set! Reboot to continue.',
    icon: <CheckCircle2 className="w-5 h-5" />,
    status: 'pending',
  },
];

// ==================== Sub-components ====================

function ProgressRing({
  progress,
  size = 180,
  strokeWidth = 10,
}: {
  progress: number;
  size?: number;
  strokeWidth?: number;
}) {
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference * (1 - Math.min(100, Math.max(0, progress)) / 100);

  return (
    <div className="relative" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90">
        {/* Track */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke="#334155"
          strokeWidth={strokeWidth}
        />
        {/* Progress arc */}
        <motion.circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke="#34d399"
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeDasharray={circumference}
          animate={{ strokeDashoffset: offset }}
          transition={{ duration: 0.6, ease: 'easeOut' }}
        />
      </svg>
      {/* Centered percentage */}
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <motion.span
          key={Math.floor(progress)}
          initial={{ opacity: 0.5, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          className="text-4xl font-bold text-slate-100 tabular-nums"
        >
          {Math.round(progress)}
          <span className="text-xl text-slate-400">%</span>
        </motion.span>
      </div>
    </div>
  );
}

function CelebrationOverlay({ onDone }: { onDone: () => void }) {
  useEffect(() => {
    const t = setTimeout(onDone, 2000);
    return () => clearTimeout(t);
  }, [onDone]);

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className="absolute inset-0 z-50 flex flex-col items-center justify-center bg-slate-950/90 backdrop-blur-sm rounded-xl"
    >
      {/* Expanding rings */}
      {[0, 1, 2].map((i) => (
        <motion.div
          key={i}
          initial={{ width: 160, height: 160, opacity: 0.6 }}
          animate={{ width: 320, height: 320, opacity: 0 }}
          transition={{ duration: 1.5, delay: i * 0.25, ease: 'easeOut' }}
          className="absolute rounded-full border-2 border-emerald-400/40"
        />
      ))}

      {/* Big checkmark */}
      <motion.div
        initial={{ scale: 0, rotate: -20 }}
        animate={{ scale: 1, rotate: 0 }}
        transition={{ type: 'spring', stiffness: 260, damping: 20, delay: 0.1 }}
        className="relative z-10 w-24 h-24 rounded-full bg-emerald-500/20 border-2 border-emerald-400 flex items-center justify-center"
      >
        <CheckCircle2 className="w-12 h-12 text-emerald-400" />
      </motion.div>

      <motion.p
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.4 }}
        className="mt-6 text-lg font-semibold text-emerald-400"
      >
        All set!
      </motion.p>
      <motion.p
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.6 }}
        className="mt-1 text-sm text-slate-400"
      >
        Rebooting in a moment…
      </motion.p>

      {/* Floating sparkles */}
      {Array.from({ length: 8 }).map((_, i) => (
        <motion.div
          key={i}
          initial={{
            opacity: 0,
            x: 0,
            y: 0,
            scale: 0,
          }}
          animate={{
            opacity: [0, 1, 0],
            x: Math.cos((i / 8) * Math.PI * 2) * 120,
            y: Math.sin((i / 8) * Math.PI * 2) * 120 - 40,
            scale: [0, 1, 0.5],
          }}
          transition={{ duration: 1.2, delay: 0.2 + i * 0.05 }}
          className="absolute"
        >
          <Sparkles className="w-4 h-4 text-emerald-400" />
        </motion.div>
      ))}
    </motion.div>
  );
}

// ==================== Main Component ====================

interface InstallationProgressWindowProps {
  testMode?: boolean;
}

export default function InstallationProgressWindow({ testMode = false }: InstallationProgressWindowProps) {
  const [, setSteps] = useState<InstallStep[]>(INSTALL_STEPS);
  const [overallProgress, setOverallProgress] = useState(0);
  const [currentPhaseIndex, setCurrentPhaseIndex] = useState(0);
  const [isInstalling, setIsInstalling] = useState(!testMode);
  const [isCompleted, setIsCompleted] = useState(false);
  const [showCancelDialog, setShowCancelDialog] = useState(false);
  const [showDetails, setShowDetails] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [downloadPercent, setDownloadPercent] = useState(0);
  const [isRollingBack, setIsRollingBack] = useState(false);
  const [rollbackStatus, setRollbackStatus] = useState<RollbackStatus | null>(null);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [timeEstimate, setTimeEstimate] = useState('Calculating…');
  const [currentDetail, setCurrentDetail] = useState('Initializing…');

  const startTimeRef = useRef(Date.now());
  const unlistenRef = useRef<(() => void) | null>(null);
  const logEndRef = useRef<HTMLDivElement>(null);

  const currentPhase = PHASES[currentPhaseIndex];

  // Auto-scroll logs
  useEffect(() => {
    if (showDetails && logEndRef.current) {
      logEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [logs, showDetails]);

  // Time estimate updater
  useEffect(() => {
    const interval = setInterval(() => {
      if (overallProgress <= 2) {
        setTimeEstimate('Calculating…');
        return;
      }
      if (overallProgress >= 99) {
        setTimeEstimate('Almost done!');
        return;
      }
      const elapsed = Date.now() - startTimeRef.current;
      const totalEstimated = elapsed / (overallProgress / 100);
      const remaining = Math.max(0, totalEstimated - elapsed);
      const minutes = Math.ceil(remaining / 60000);
      setTimeEstimate(
        minutes <= 1
          ? 'Less than a minute remaining'
          : `About ${minutes} minutes remaining`
      );
    }, 8000);
    return () => clearInterval(interval);
  }, [overallProgress]);

  const addLog = useCallback((message: string, type: LogEntry['type'] = 'info') => {
    const time = new Date().toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    setLogs((prev) => [...prev, { time, message, type }]);
  }, []);

  useEffect(() => {
    writeTestState(TEST_STATE_PATH, {
      screen: 'progress',
      stage: 'preparing',
      started: !testMode,
      testMode,
      timestamp: Date.now(),
    }).catch(() => {});

    if (!testMode) {
      runInstallationStages();
      setupDownloadListener();
    }

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
        const downloadProgress = Math.floor(progress.percent * 0.4); // 40% of total
        setOverallProgress(25 + downloadProgress);
        setCurrentDetail(`Downloading ${progress.stage} (${progress.percent}%)`);
        addLog(`Download progress: ${progress.percent}% — ${progress.stage}`);
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

      // Phase 0: Prepare staging
      setCurrentPhaseIndex(0);
      setCurrentDetail('Analyzing disk layout…');
      addLog('Starting installation staging…');
      addLog(`Target Linux partition size: ${config.linux_size_gb} GB`);

      updateStepStatus('prepare', 'in-progress');
      setOverallProgress(5);

      const stagingInfo: StagingInfo = await prepareStaging(config, 'OSWORLD');

      addLog(`Created boot partition on drive ${stagingInfo.boot_partition_letter}`, 'success');
      addLog(`Linux partition number: ${stagingInfo.linux_partition_number}`, 'success');
      updateStepStatus('prepare', 'completed');
      setOverallProgress(20);

      // Phase 1: Download ISO
      setCurrentPhaseIndex(1);
      setCurrentDetail('Connecting to mirror…');
      addLog('Beginning ISO download from geo.mirror.pkgbuild.com…');
      updateStepStatus('download', 'in-progress');
      setOverallProgress(25);

      await downloadAndStageIso(stagingInfo.boot_partition_letter, config);

      updateStepStatus('download', 'completed');
      setOverallProgress(60);
      addLog('ISO downloaded and staged successfully', 'success');

      // Phase 2: Verify (brief)
      setCurrentPhaseIndex(2);
      setCurrentDetail('Verifying file integrity…');
      addLog('Verifying ISO checksum and extracted boot files…');
      setOverallProgress(65);
      await writeTestState(TEST_STATE_PATH, {
        screen: 'progress',
        stage: 'verify_start',
        timestamp: Date.now(),
      }).catch(() => {});
      await new Promise((r) => setTimeout(r, 900));
      await writeTestState(TEST_STATE_PATH, {
        screen: 'progress',
        stage: 'verify_complete',
        timestamp: Date.now(),
      }).catch(() => {});
      addLog('Verification passed', 'success');
      setOverallProgress(70);

      // Phase 3: Install rEFInd
      setCurrentPhaseIndex(3);
      setCurrentDetail('Installing rEFInd bootloader…');
      addLog('Downloading and installing rEFInd bootloader to ESP…');
      updateStepStatus('bootloader', 'in-progress');
      setOverallProgress(75);

      await installRefind();

      addLog('rEFInd installed and configured', 'success');
      addLog('Created menu entries: OSWorld Installer, AltOS Recovery');
      updateStepStatus('bootloader', 'completed');
      setOverallProgress(85);

      // Phase 4: Finalize
      setCurrentPhaseIndex(4);
      setCurrentDetail('Writing final configuration…');
      addLog('Writing install-config.json to boot partition…');
      setOverallProgress(90);
      await writeTestState(TEST_STATE_PATH, {
        screen: 'progress',
        stage: 'finalize_start',
        timestamp: Date.now(),
      }).catch(() => {});
      await new Promise((r) => setTimeout(r, 600));
      await writeTestState(TEST_STATE_PATH, {
        screen: 'progress',
        stage: 'finalize_complete',
        timestamp: Date.now(),
      }).catch(() => {});
      addLog('Configuration saved', 'success');
      addLog('Installation staging complete', 'success');
      setOverallProgress(100);

      updateStepStatus('reboot', 'completed');
      setIsCompleted(true);
      setIsInstalling(false);
      setCurrentDetail('Ready to reboot');
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Installation failed';
      setError(message);
      setIsInstalling(false);
      addLog(`Installation error: ${message}`, 'error');

      setSteps((prev) =>
        prev.map((step) =>
          step.status === 'in-progress' ? { ...step, status: 'error' } : step
        )
      );

      // Auto-rollback
      setIsRollingBack(true);
      setCurrentDetail('Rolling back changes…');
      addLog('Initiating automatic rollback…', 'error');
      try {
        const status = await rollbackStaging('ROLLBACK');
        setRollbackStatus(status);
        setIsRollingBack(false);
        status.actions.forEach((a) =>
          addLog(
            `${a.success ? '✓' : '✗'} ${a.description}${a.warning ? ` — ${a.warning}` : ''}`,
            a.success ? 'success' : 'error'
          )
        );
      } catch (rollbackErr) {
        setIsRollingBack(false);
        setRollbackStatus({
          success: false,
          actions: [],
          manual_steps: ['Rollback failed. You may need to run Disk Management to clean up leftover partitions.'],
          log_path: 'C:\\ProgramData\\OSWorld\\logs\\rollback.log',
        });
        addLog('Rollback failed', 'error');
      }
    }
  };

  const runStagesRef = useRef(runInstallationStages);
  const setupListenerRef = useRef(setupDownloadListener);
  runStagesRef.current = runInstallationStages;
  setupListenerRef.current = setupDownloadListener;

  useEffect(() => {
    if (!testMode || isInstalling || isCompleted) return;
    const t = setTimeout(() => {
      setIsInstalling(true);
      runStagesRef.current();
      setupListenerRef.current();
    }, 1200);
    return () => clearTimeout(t);
  }, [testMode]);

  const updateStepStatus = (stepId: string, status: InstallStep['status']) => {
    setSteps((prev) =>
      prev.map((step) => (step.id === stepId ? { ...step, status } : step))
    );
  };

  const handleCancel = async () => {
    try {
      await cancelInstallation();
      setShowCancelDialog(false);
      setIsInstalling(false);
      setError('Installation was cancelled by user');
      addLog('Installation cancelled by user', 'error');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to cancel installation');
    }
  };

  const handleRestart = () => {
    window.location.reload();
  };

  const handleReboot = useCallback(async () => {
    try {
      await rebootToInstaller();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to initiate reboot');
    }
  }, []);

  // Auto-reboot after celebration
  useEffect(() => {
    if (!isCompleted) return;
    const timer = setTimeout(() => {
      handleReboot();
    }, 2000);
    return () => clearTimeout(timer);
  }, [isCompleted, handleReboot]);

  // Derived checklist state from phases
  const phaseChecklist = PHASES.map((phase, idx) => ({
    ...phase,
    done: idx < currentPhaseIndex || isCompleted,
    active: idx === currentPhaseIndex && !isCompleted,
  }));

  return (
    <div className="relative space-y-6">
      {/* Celebration overlay on completion */}
      <AnimatePresence>
        {isCompleted && <CelebrationOverlay onDone={() => {}} />}
      </AnimatePresence>

      {/* Header */}
      <div className="text-center space-y-1">
        <h2 className="text-xl font-semibold text-slate-100">
          {error && !isRollingBack
            ? 'Installation Failed'
            : isCompleted
            ? 'Ready to Reboot'
            : testMode && !isInstalling
            ? 'Ready to Install'
            : 'Installing AltOS'}
        </h2>
        <p className="text-sm text-slate-400">
          {error && !isRollingBack
            ? 'Something went wrong. We tried to roll back any changes.'
            : isCompleted
            ? 'All files are staged. Rebooting automatically…'
            : testMode && !isInstalling
            ? 'Review your settings before starting the installation.'
            : 'Please keep your computer plugged in and awake.'}
        </p>
      </div>

      {/* Rollback in Progress */}
      <AnimatePresence>
        {isRollingBack && (
          <motion.div
            initial={{ opacity: 0, y: 4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            className="border-l-4 border-altos-blue bg-[#1a1d21] rounded-r-lg p-5"
          >
            <div className="flex items-center gap-3 mb-2">
              <motion.div
                animate={{ rotate: 360 }}
                transition={{ repeat: Infinity, duration: 1, ease: 'linear' }}
              >
                <Cog className="w-5 h-5 text-altos-blue" />
              </motion.div>
              <h4 className="font-medium text-altos-text">Rolling back changes…</h4>
            </div>
            <p className="text-sm text-altos-text-secondary">
              Your system is being restored to its original state. Please wait.
            </p>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Error Message */}
      <AnimatePresence>
        {error && !isRollingBack && (
          <motion.div
            initial={{ opacity: 0, y: 4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            className="border-l-4 border-rose-500 bg-[#1a1d21] rounded-r-lg p-4"
          >
            <div className="flex items-start gap-3">
              <AlertTriangle className="w-5 h-5 text-rose-400 flex-shrink-0 mt-0.5" />
              <div>
                <h4 className="font-medium text-slate-100 text-sm mb-1">Installation Failed</h4>
                <p className="text-sm text-slate-400">{error}</p>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Rollback Complete */}
      <AnimatePresence>
        {rollbackStatus && !isRollingBack && (
          <motion.div
            initial={{ opacity: 0, y: 4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            className={`border-l-4 rounded-r-lg p-5 ${
              rollbackStatus.success
                ? 'border-emerald-500 bg-emerald-500/5'
                : 'border-amber-500 bg-amber-500/5'
            }`}
          >
            <div className="flex items-start gap-3 mb-4">
              {rollbackStatus.success ? (
                <CheckCircle2 className="w-6 h-6 text-emerald-400 flex-shrink-0" />
              ) : (
                <AlertTriangle className="w-6 h-6 text-amber-400 flex-shrink-0" />
              )}
              <div>
                <h4 className="font-medium text-slate-100 mb-1">
                  {rollbackStatus.success
                    ? 'Your system has been restored'
                    : 'Rollback completed with warnings'}
                </h4>
                <p className="text-sm text-slate-400">
                  {rollbackStatus.success
                    ? 'No changes were made to your system. You can try again safely.'
                    : 'Some items could not be rolled back automatically. See below for manual steps.'}
                </p>
              </div>
            </div>

            {rollbackStatus.actions.length > 0 && (
              <div className="space-y-2 mb-4">
                <h5 className="text-sm font-medium text-slate-200">Actions taken:</h5>
                {rollbackStatus.actions.map((action, actionIdx) => (
                  <div
                    key={actionIdx}
                    className={`text-sm p-2.5 rounded-lg ${
                      action.success
                        ? 'bg-emerald-500/10 text-emerald-300'
                        : 'bg-rose-500/10 text-rose-300'
                    }`}
                  >
                    <div className="flex items-start gap-2">
                      <span className="flex-shrink-0 mt-0.5">{action.success ? '✓' : '✗'}</span>
                      <span>{action.description}</span>
                    </div>
                    {action.warning && (
                      <p className="text-xs mt-1 text-amber-300 ml-4">{action.warning}</p>
                    )}
                  </div>
                ))}
              </div>
            )}

            {rollbackStatus.manual_steps.length > 0 && (
              <div className="bg-slate-900 border border-slate-800 rounded-lg p-4">
                <h5 className="text-sm font-medium text-slate-200 mb-2">Manual steps needed:</h5>
                <ul className="text-sm text-slate-400 space-y-1">
                  {rollbackStatus.manual_steps.map((step, idx) => (
                    <li key={idx} className="flex items-start gap-2">
                      <span className="text-slate-500 mt-0.5">•</span>
                      <span>{step}</span>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            <p className="text-xs text-slate-500 mt-3">
              Log saved to: {rollbackStatus.log_path}
            </p>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Main Progress UI */}
      {!error && !isRollingBack && !rollbackStatus && (
        <div className="space-y-6">
          {/* Test mode: Start Installation prompt */}
          {testMode && !isInstalling && !isCompleted && (
            <div className="bg-gradient-to-b from-slate-900 to-slate-950 border border-slate-800 rounded-2xl p-8 flex flex-col items-center space-y-6">
              <div className="w-20 h-20 rounded-full bg-emerald-500/10 border-2 border-emerald-400 flex items-center justify-center">
                <CheckCircle2 className="w-10 h-10 text-emerald-400" />
              </div>
              <div className="text-center space-y-2">
                <h3 className="text-lg font-semibold text-slate-100">Ready to Install</h3>
                <p className="text-sm text-slate-400 max-w-xs mx-auto">
                  All settings configured. Click below to begin installation.
                </p>
              </div>
              <button
                onClick={() => {
                  setIsInstalling(true);
                  runInstallationStages();
                  setupDownloadListener();
                }}
                className="flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white bg-emerald-500 hover:bg-emerald-600 transition-colors"
              >
                <Power className="w-5 h-5" />
                <span>Start Installation</span>
              </button>
            </div>
          )}

          {/* Circular progress + step label */}
          {(isInstalling || isCompleted) && (
          <div className="bg-gradient-to-b from-slate-900 to-slate-950 border border-slate-800 rounded-2xl p-8 flex flex-col items-center space-y-6">
            {/* Ring */}
            <ProgressRing progress={overallProgress} size={180} strokeWidth={10} />

            {/* Step label with cross-fade */}
            <div className="text-center space-y-2 min-h-[80px]">
              <AnimatePresence mode="wait">
                <motion.div
                  key={currentPhase.id + (isCompleted ? '-done' : '')}
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -8 }}
                  transition={{ duration: 0.3 }}
                  className="space-y-1"
                >
                  <h3 className="text-lg font-semibold text-slate-100">
                    {isCompleted ? 'Installation complete!' : currentPhase.label}
                  </h3>
                  <p className="text-sm text-slate-400 max-w-xs mx-auto">
                    {isCompleted
                      ? 'Your PC will restart into the AltOS Installer.'
                      : currentPhase.description}
                  </p>
                </motion.div>
              </AnimatePresence>

              {/* Current operation detail */}
              {!isCompleted && (
                <motion.p
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  className="text-xs text-slate-500 font-mono"
                >
                  {currentDetail}
                </motion.p>
              )}
            </div>

            {/* Time estimate */}
            <div className="flex items-center gap-2 text-xs text-slate-500">
              <Clock className="w-3.5 h-3.5" />
              <span>{timeEstimate}</span>
            </div>

            {/* Download sub-progress */}
            {currentPhase.id === 'download' && downloadPercent > 0 && !isCompleted && (
              <div className="w-full max-w-xs">
                <div className="flex items-center justify-between mb-1.5">
                  <span className="text-[11px] text-slate-500 uppercase tracking-wider font-medium">
                    ISO Download
                  </span>
                  <span className="text-xs font-medium text-emerald-400">{downloadPercent}%</span>
                </div>
                <div className="h-1.5 bg-slate-800 rounded-full overflow-hidden">
                  <motion.div
                    className="h-full bg-emerald-400 rounded-full"
                    animate={{ width: `${downloadPercent}%` }}
                    transition={{ duration: 0.3 }}
                  />
                </div>
              </div>
            )}
          </div>
          )}

          {/* Details expander */}
          <div className="bg-[#1a1d21] border border-slate-800 rounded-xl overflow-hidden">
            <button
              onClick={() => setShowDetails((s) => !s)}
              className="w-full flex items-center justify-between px-5 py-3 text-sm font-medium text-slate-400 hover:text-slate-200 transition-colors"
            >
              <span className="flex items-center gap-2">
                <Terminal className="w-4 h-4" />
                Details
              </span>
              <motion.span animate={{ rotate: showDetails ? 180 : 0 }} transition={{ duration: 0.2 }}>
                <ChevronDown className="w-4 h-4" />
              </motion.span>
            </button>

            <AnimatePresence>
              {showDetails && (
                <motion.div
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: 'auto' }}
                  exit={{ opacity: 0, height: 0 }}
                  transition={{ duration: 0.25, ease: 'easeInOut' }}
                  className="overflow-hidden"
                >
                  <div className="px-5 pb-5 space-y-4 border-t border-slate-800 pt-4">
                    {/* Phase checklist */}
                    <div className="space-y-2">
                      {phaseChecklist.map((phase) => (
                        <motion.div
                          key={phase.id}
                          initial={false}
                          animate={{
                            opacity: phase.done || phase.active ? 1 : 0.5,
                          }}
                          className="flex items-center gap-3"
                        >
                          <motion.div
                            initial={false}
                            animate={{
                              scale: phase.done ? [1, 1.3, 1] : 1,
                            }}
                            transition={{ duration: 0.3 }}
                            className={`w-5 h-5 rounded-full flex items-center justify-center flex-shrink-0 ${
                              phase.done
                                ? 'bg-emerald-500/20 text-emerald-400'
                                : phase.active
                                ? 'bg-emerald-500/10 text-emerald-400'
                                : 'bg-slate-800 text-slate-600'
                            }`}
                          >
                            {phase.done ? (
                              <Check className="w-3 h-3" />
                            ) : phase.active ? (
                              <motion.div
                                animate={{ rotate: 360 }}
                                transition={{ repeat: Infinity, duration: 1.5, ease: 'linear' }}
                              >
                                <Circle className="w-3 h-3" />
                              </motion.div>
                            ) : (
                              <Circle className="w-3 h-3" />
                            )}
                          </motion.div>
                          <span
                            className={`text-sm ${
                              phase.done
                                ? 'text-emerald-400 line-through decoration-emerald-500/30'
                                : phase.active
                                ? 'text-slate-200'
                                : 'text-slate-500'
                            }`}
                          >
                            {phase.label.replace('…', '')}
                          </span>
                        </motion.div>
                      ))}
                    </div>

                    {/* Log output */}
                    <div className="bg-slate-950 border border-slate-800 rounded-lg overflow-hidden">
                      <div className="px-3 py-1.5 bg-slate-900 border-b border-slate-800 flex items-center justify-between">
                        <span className="text-[10px] uppercase tracking-wider font-semibold text-slate-500">
                          Operation Log
                        </span>
                        <span className="text-[10px] text-slate-600">{logs.length} entries</span>
                      </div>
                      <div className="p-3 max-h-40 overflow-y-auto font-mono text-[11px] leading-relaxed space-y-1">
                        {logs.length === 0 && (
                          <span className="text-slate-600">Waiting for operations…</span>
                        )}
                        {logs.map((log, i) => (
                          <div key={i} className="flex gap-2">
                            <span className="text-slate-600 shrink-0">[{log.time}]</span>
                            <span
                              className={
                                log.type === 'success'
                                  ? 'text-emerald-400'
                                  : log.type === 'error'
                                  ? 'text-rose-400'
                                  : 'text-slate-400'
                              }
                            >
                              {log.message}
                            </span>
                          </div>
                        ))}
                        <div ref={logEndRef} />
                      </div>
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </div>
      )}

      {/* Cancel dialog */}
      <AnimatePresence>
        {showCancelDialog && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 flex items-center justify-center p-4"
          >
            <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={() => setShowCancelDialog(false)} />
            <motion.div
              initial={{ opacity: 0, scale: 0.95, y: 16 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: 16 }}
              transition={{ type: 'spring', damping: 25, stiffness: 300 }}
              className="relative w-full max-w-md rounded-2xl bg-gradient-to-b from-slate-900 to-slate-950 border border-slate-800 shadow-2xl p-6"
            >
              <div className="flex items-start gap-4">
                <div className="w-10 h-10 bg-amber-500/10 rounded-full flex items-center justify-center flex-shrink-0">
                  <AlertTriangle className="w-5 h-5 text-amber-400" />
                </div>
                <div className="flex-1">
                  <h3 className="text-base font-semibold text-slate-100 mb-2">Stop installation?</h3>
                  <p className="text-sm text-slate-400 mb-5">
                    Cancelling may leave your system in an inconsistent state. We recommend letting the installation
                    complete.
                  </p>
                  <div className="flex gap-3">
                    <button
                      onClick={() => setShowCancelDialog(false)}
                      className="px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-200 font-medium hover:bg-slate-700 transition-colors"
                    >
                      Continue
                    </button>
                    <button
                      onClick={handleCancel}
                      className="px-4 py-2 bg-rose-500 text-white rounded-lg font-medium hover:bg-rose-600 transition-colors"
                    >
                      Yes, stop
                    </button>
                  </div>
                </div>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Bottom actions */}
      <div className="flex flex-col items-center gap-4 pt-2">
        {isInstalling && !isCompleted && (
          <button
            onClick={() => setShowCancelDialog(true)}
            className="text-xs text-slate-500 hover:text-rose-400 underline underline-offset-2 transition-colors"
          >
            Stop installation
          </button>
        )}

        {error && !rollbackStatus && (
          <button
            onClick={handleRestart}
            className="flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white bg-altos-blue hover:bg-altos-blue-hover transition-colors"
          >
            <RotateCcw className="w-5 h-5" />
            <span>Restart Installer</span>
          </button>
        )}

        {rollbackStatus && !isRollingBack && (
          <div className="flex gap-3">
            <button
              onClick={handleRestart}
              className="flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white bg-altos-blue hover:bg-altos-blue-hover transition-colors"
            >
              <RotateCcw className="w-5 h-5" />
              <span>Try Again</span>
            </button>
            <button
              onClick={() => window.open('https://github.com/osworld-installer/support', '_blank')}
              className="flex items-center gap-2 px-5 py-2.5 rounded-lg font-medium text-slate-400 bg-slate-800 hover:text-slate-200 border border-slate-700 hover:border-slate-600 transition-colors"
            >
              <AlertTriangle className="w-5 h-5" />
              <span>Get Help</span>
            </button>
          </div>
        )}

        {isCompleted && (
          <button
            onClick={handleReboot}
            className="flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white bg-emerald-500 hover:bg-emerald-600 transition-colors"
          >
            <Power className="w-5 h-5" />
            <span>Reboot Now</span>
          </button>
        )}
      </div>

      {/* Tips */}
      {!isCompleted && !error && !rollbackStatus && (
        <div className="bg-[#1a1d21] border border-slate-800 rounded-xl p-4">
          <div className="flex items-start gap-3">
            <div className="w-8 h-8 bg-blue-500/10 rounded-lg flex items-center justify-center flex-shrink-0">
              <span className="text-blue-400 font-bold text-xs">?</span>
            </div>
            <div>
              <h4 className="font-medium text-slate-200 text-sm mb-1">While you wait</h4>
              <ul className="text-sm text-slate-400 space-y-1">
                <li>• Keep your laptop plugged in</li>
                <li>• Don't put your computer to sleep</li>
                <li>• The staging process takes 10–20 minutes depending on your connection</li>
              </ul>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
