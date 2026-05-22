import { useState, useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Cpu,
  HardDrive,
  MemoryStick,
  Shield,
  Lock,
  Monitor,
  CheckCircle2,
  AlertTriangle,
  XCircle,
  ArrowLeft,
  RefreshCw,
  Loader2,
  Wrench,
  X,
  ChevronRight,
} from 'lucide-react';
import { detectSystemInfo, detectPcManufacturer } from '../lib/tauri';
import type { SystemInfo, PcManufacturerInfo } from '../types';

interface SystemCheckWindowProps {
  onNext: () => void;
  onBack: () => void;
}

type CheckStatus = 'ok' | 'warning' | 'error';

interface CheckDef {
  key: string;
  icon: React.ReactNode;
  label: string;
  status: CheckStatus;
  value: string;
  message?: string;
}

interface GuidanceModalProps {
  open: boolean;
  onClose: () => void;
  title: string;
  manufacturer: PcManufacturerInfo | null;
  children: React.ReactNode;
}

function GuidanceModal({ open, onClose, title, manufacturer, children }: GuidanceModalProps) {
  return (
    <AnimatePresence>
      {open && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="fixed inset-0 z-50 flex items-center justify-center p-4"
        >
          <div
            className="absolute inset-0 bg-black/60 backdrop-blur-sm"
            onClick={onClose}
          />
          <motion.div
            initial={{ opacity: 0, scale: 0.95, y: 16 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: 16 }}
            transition={{ type: 'spring', damping: 25, stiffness: 300 }}
            className="relative w-full max-w-lg rounded-2xl bg-gradient-to-b from-slate-900 to-slate-950 border border-slate-800 shadow-2xl overflow-hidden"
          >
            <div className="flex items-center justify-between px-6 py-4 border-b border-slate-800">
              <h3 className="text-lg font-semibold text-slate-100">{title}</h3>
              <button
                onClick={onClose}
                className="p-1.5 rounded-lg text-slate-400 hover:text-slate-100 hover:bg-slate-800 transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="px-6 py-5 space-y-4 text-slate-300 text-sm leading-relaxed max-h-[60vh] overflow-y-auto">
              {manufacturer && (
                <div className="flex items-center gap-3 p-3 rounded-xl bg-slate-800/50 border border-slate-700/50">
                  <div className="w-9 h-9 rounded-lg bg-slate-800 flex items-center justify-center text-slate-200 font-bold text-xs">
                    {manufacturer.manufacturer[0]}
                  </div>
                  <div>
                    <p className="text-xs text-slate-400">Detected manufacturer</p>
                    <p className="font-medium text-slate-200">{manufacturer.manufacturer}</p>
                  </div>
                  <div className="ml-auto text-right">
                    <p className="text-xs text-slate-400">Boot menu</p>
                    <p className="font-medium text-emerald-400">{manufacturer.boot_menu_key}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-xs text-slate-400">BIOS setup</p>
                    <p className="font-medium text-emerald-400">{manufacturer.bios_key}</p>
                  </div>
                </div>
              )}
              {children}
            </div>

            <div className="px-6 py-4 border-t border-slate-800 flex justify-end">
              <button
                onClick={onClose}
                className="px-4 py-2 rounded-lg bg-slate-800 text-slate-200 text-sm font-medium hover:bg-slate-700 transition-colors"
              >
                Got it
              </button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

export default function SystemCheckWindow({ onNext, onBack }: SystemCheckWindowProps) {
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [manufacturer, setManufacturer] = useState<PcManufacturerInfo | null>(null);
  const [phase, setPhase] = useState<'loading' | 'success' | 'failed' | 'error'>('loading');
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [activeModal, setActiveModal] = useState<'secureboot' | 'bitlocker' | null>(null);

  const runChecks = useCallback(async () => {
    setPhase('loading');
    setErrorMsg(null);
    setSystemInfo(null);

    try {
      const [info, mfr] = await Promise.all([
        detectSystemInfo(),
        detectPcManufacturer(),
      ]);
      setSystemInfo(info);
      setManufacturer(mfr);

      const hasErrors = info.secure_boot_enabled || info.bitlocker_enabled;
      if (hasErrors) {
        setPhase('failed');
      } else {
        setPhase('success');
        setTimeout(() => {
          onNext();
        }, 1500);
      }
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Failed to detect system information');
      setPhase('error');
    }
  }, [onNext]);

  useEffect(() => {
    runChecks();
  }, [runChecks]);

  const checks: CheckDef[] = systemInfo
    ? [
        {
          key: 'windows',
          icon: <Monitor className="w-5 h-5" />,
          label: 'Windows Version',
          status: 'ok',
          value: systemInfo.windows_version,
        },
        {
          key: 'disk',
          icon: <HardDrive className="w-5 h-5" />,
          label: 'Disk Free Space',
          status: systemInfo.disk_free_space_gb < 20 ? 'warning' : 'ok',
          value: `${systemInfo.disk_free_space_gb} GB`,
          message:
            systemInfo.disk_free_space_gb < 20
              ? "You'll need at least 20 GB of free space to install AltOS comfortably."
              : undefined,
        },
        {
          key: 'ram',
          icon: <MemoryStick className="w-5 h-5" />,
          label: 'RAM',
          status: systemInfo.ram_gb < 4 ? 'warning' : 'ok',
          value: `${systemInfo.ram_gb} GB`,
          message:
            systemInfo.ram_gb < 4
              ? "4 GB of RAM is recommended for a smooth experience."
              : undefined,
        },
        {
          key: 'cpu',
          icon: <Cpu className="w-5 h-5" />,
          label: 'Processor',
          status: 'ok',
          value: systemInfo.cpu_info,
        },
        {
          key: 'secureboot',
          icon: <Shield className="w-5 h-5" />,
          label: 'Secure Boot',
          status: systemInfo.secure_boot_enabled ? 'error' : 'ok',
          value: systemInfo.secure_boot_enabled ? 'Enabled' : 'Disabled',
          message: systemInfo.secure_boot_enabled
            ? "Secure Boot blocks non-Windows operating systems. It needs to be turned off in your BIOS."
            : undefined,
        },
        {
          key: 'bitlocker',
          icon: <Lock className="w-5 h-5" />,
          label: 'BitLocker',
          status: systemInfo.bitlocker_enabled ? 'error' : 'ok',
          value: systemInfo.bitlocker_enabled ? 'Enabled' : 'Disabled',
          message: systemInfo.bitlocker_enabled
            ? "BitLocker encryption must be suspended before installing AltOS, or your data could become inaccessible."
            : undefined,
        },
      ]
    : [];

  const passedCount = checks.filter((c) => c.status === 'ok').length;
  const totalCount = checks.length;
  const failedChecks = checks.filter((c) => c.status !== 'ok');

  return (
    <div className="relative space-y-6">
      {/* Loading State */}
      <AnimatePresence mode="wait">
        {phase === 'loading' && (
          <motion.div
            key="loading"
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            className="flex flex-col items-center justify-center py-16 space-y-6"
          >
            <div className="relative">
              <motion.div
                animate={{ rotate: 360 }}
                transition={{ repeat: Infinity, duration: 1.2, ease: 'linear' }}
                className="w-20 h-20 rounded-full border-4 border-slate-800 border-t-altos-blue"
              />
              <div className="absolute inset-0 flex items-center justify-center">
                <Loader2 className="w-8 h-8 text-altos-blue animate-spin" />
              </div>
            </div>
            <div className="text-center space-y-2">
              <h3 className="text-lg font-semibold text-slate-100">
                Checking your system…
              </h3>
              <p className="text-sm text-slate-400 max-w-xs mx-auto">
                We're scanning your hardware and security settings to make sure everything is ready for AltOS.
              </p>
            </div>
          </motion.div>
        )}

        {/* Success Pulse */}
        {phase === 'success' && (
          <motion.div
            key="success"
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.95 }}
            className="flex flex-col items-center justify-center py-16 space-y-6"
          >
            <motion.div
              initial={{ scale: 0 }}
              animate={{ scale: [0, 1.2, 1] }}
              transition={{ duration: 0.6, ease: 'easeOut' }}
              className="relative"
            >
              <motion.div
                animate={{ opacity: [0.4, 0, 0.4], scale: [1, 1.6, 1] }}
                transition={{ repeat: Infinity, duration: 2, ease: 'easeInOut' }}
                className="absolute inset-0 rounded-full bg-emerald-500/20"
              />
              <div className="w-20 h-20 rounded-full bg-emerald-500/10 border-2 border-emerald-400 flex items-center justify-center">
                <CheckCircle2 className="w-10 h-10 text-emerald-400" />
              </div>
            </motion.div>
            <div className="text-center space-y-1">
              <h3 className="text-lg font-semibold text-emerald-400">
                Your PC is ready!
              </h3>
              <p className="text-sm text-slate-400">
                All checks passed. Moving on…
              </p>
            </div>
          </motion.div>
        )}

        {/* Failed / Expanded State */}
        {(phase === 'failed' || phase === 'error') && (
          <motion.div
            key="failed"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="space-y-5"
          >
            {/* Header */}
            <div className="text-center space-y-1">
              <h2 className="text-xl font-semibold text-slate-100">System Check</h2>
              <p className="text-sm text-slate-400">
                We found a few things that need your attention before installing AltOS.
              </p>
            </div>

            {/* Error Banner (top-level detection failure) */}
            {errorMsg && (
              <motion.div
                initial={{ opacity: 0, y: 4 }}
                animate={{ opacity: 1, y: 0 }}
                className="flex items-start gap-3 p-4 rounded-xl bg-rose-500/10 border border-rose-500/20"
              >
                <XCircle className="w-5 h-5 text-rose-400 flex-shrink-0 mt-0.5" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-rose-300">Something went wrong</p>
                  <p className="text-sm text-rose-200/70 mt-0.5">{errorMsg}</p>
                </div>
                <button
                  onClick={runChecks}
                  className="flex items-center gap-1.5 text-sm font-medium text-rose-300 hover:text-rose-200 transition-colors"
                >
                  <RefreshCw className="w-4 h-4" />
                  Retry
                </button>
              </motion.div>
            )}

            {/* Passed pills */}
            {!errorMsg && passedCount > 0 && (
              <motion.div
                initial={{ opacity: 0, y: 4 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.1 }}
                className="flex flex-wrap items-center gap-2"
              >
                <span className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-emerald-500/10 border border-emerald-500/20 text-xs font-medium text-emerald-400">
                  <CheckCircle2 className="w-3.5 h-3.5" />
                  {passedCount}/{totalCount} checks passed
                </span>
                {checks
                  .filter((c) => c.status === 'ok')
                  .map((c) => (
                    <span
                      key={c.key}
                      className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-slate-800 text-xs text-slate-400"
                    >
                      {c.icon}
                      {c.label}
                    </span>
                  ))}
              </motion.div>
            )}

            {/* Failed check rows */}
            {!errorMsg && failedChecks.length > 0 && (
              <motion.div
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: 'auto' }}
                transition={{ duration: 0.4, ease: 'easeInOut' }}
                className="overflow-hidden"
              >
                <div className="bg-gradient-to-b from-slate-900 to-slate-950 border border-slate-800 rounded-xl overflow-hidden">
                  {failedChecks.map((check, index) => (
                    <motion.div
                      key={check.key}
                      initial={{ opacity: 0, x: -12 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ delay: 0.15 + index * 0.08 }}
                      className={`flex items-start gap-4 px-5 py-4 ${
                        index < failedChecks.length - 1 ? 'border-b border-slate-800' : ''
                      }`}
                    >
                      <div
                        className={`w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 ${
                          check.status === 'error'
                            ? 'bg-rose-500/10 text-rose-400'
                            : 'bg-amber-500/10 text-amber-400'
                        }`}
                      >
                        {check.icon}
                      </div>

                      <div className="flex-1 min-w-0 space-y-1">
                        <div className="flex items-center justify-between gap-3">
                          <p className="text-sm font-medium text-slate-200">{check.label}</p>
                          <span
                            className={`text-xs font-semibold px-2 py-0.5 rounded-full ${
                              check.status === 'error'
                                ? 'bg-rose-500/10 text-rose-400'
                                : 'bg-amber-500/10 text-amber-400'
                            }`}
                          >
                            {check.value}
                          </span>
                        </div>

                        {check.message && (
                          <p
                            className={`text-sm leading-relaxed ${
                              check.status === 'error' ? 'text-rose-300' : 'text-amber-300'
                            }`}
                          >
                            {check.message}
                          </p>
                        )}

                        {/* Fix button for blocking issues */}
                        {check.status === 'error' && (
                          <button
                            onClick={() =>
                              setActiveModal(
                                check.key === 'secureboot' ? 'secureboot' : 'bitlocker'
                              )
                            }
                            className="inline-flex items-center gap-1.5 mt-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 transition-colors"
                          >
                            <Wrench className="w-3.5 h-3.5" />
                            Fix
                            <ChevronRight className="w-3 h-3" />
                          </button>
                        )}
                      </div>

                      <div className="flex-shrink-0 mt-2">
                        {check.status === 'error' ? (
                          <XCircle className="w-5 h-5 text-rose-400" />
                        ) : (
                          <AlertTriangle className="w-5 h-5 text-amber-400" />
                        )}
                      </div>
                    </motion.div>
                  ))}
                </div>
              </motion.div>
            )}

            {/* Summary banner */}
            {!errorMsg && failedChecks.some((c) => c.status === 'error') && (
              <motion.div
                initial={{ opacity: 0, y: 4 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.3 }}
                className="flex items-start gap-3 p-4 rounded-xl bg-rose-500/10 border border-rose-500/20"
              >
                <AlertTriangle className="w-5 h-5 text-rose-400 flex-shrink-0 mt-0.5" />
                <div>
                  <p className="text-sm font-medium text-rose-300">Action required</p>
                  <p className="text-sm text-rose-200/70 mt-0.5">
                    Please resolve the issues above before continuing. These settings will prevent a successful installation.
                  </p>
                </div>
              </motion.div>
            )}

            {/* Navigation */}
            <div className="flex justify-between pt-2">
              <button
                onClick={onBack}
                className="flex items-center gap-2 px-5 py-2.5 rounded-xl font-medium text-slate-400 hover:text-slate-200 hover:bg-slate-800 transition-colors duration-150"
              >
                <ArrowLeft className="w-5 h-5" />
                <span>Back</span>
              </button>

              <button
                onClick={runChecks}
                className="flex items-center gap-2 px-5 py-2.5 rounded-xl font-medium text-slate-300 bg-slate-800 hover:bg-slate-700 border border-slate-700 transition-colors duration-150"
              >
                <RefreshCw className="w-4 h-4" />
                <span>Re-check</span>
              </button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Secure Boot Guidance Modal */}
      <GuidanceModal
        open={activeModal === 'secureboot'}
        onClose={() => setActiveModal(null)}
        title="How to disable Secure Boot"
        manufacturer={manufacturer}
      >
        <div className="space-y-4">
          <p>
            Secure Boot is a security feature that only allows Windows to start. To install AltOS, you'll need to turn it off temporarily in your BIOS.
          </p>

          <ol className="space-y-3 list-decimal list-inside marker:text-slate-500">
            <li>
              <span className="font-medium text-slate-200">Restart your PC</span> and repeatedly press the{' '}
              <span className="px-1.5 py-0.5 rounded bg-slate-800 text-emerald-400 font-mono text-xs">
                {manufacturer?.boot_menu_key ?? 'F2 / F10 / F12'}
              </span>{' '}
              key as it starts up.
            </li>
            <li>
              Once inside the BIOS/UEFI settings, look for a tab called{' '}
              <span className="font-medium text-slate-200">Security</span>,{' '}
              <span className="font-medium text-slate-200">Boot</span>, or{' '}
              <span className="font-medium text-slate-200">Authentication</span>.
            </li>
            <li>
              Find the <span className="font-medium text-slate-200">Secure Boot</span> option and set it to{' '}
              <span className="px-1.5 py-0.5 rounded bg-slate-800 text-rose-400 font-mono text-xs">
                Disabled
              </span>
              .
            </li>
            <li>
              Save changes and exit (usually <span className="font-mono text-xs text-slate-400">F10</span>).
            </li>
          </ol>

          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/20 text-amber-300 text-xs">
            <strong>Tip:</strong> If you can't find the option, search for "Secure Boot" in the BIOS search bar (available on most modern systems).
          </div>
        </div>
      </GuidanceModal>

      {/* BitLocker Guidance Modal */}
      <GuidanceModal
        open={activeModal === 'bitlocker'}
        onClose={() => setActiveModal(null)}
        title="How to suspend BitLocker"
        manufacturer={manufacturer}
      >
        <div className="space-y-4">
          <p>
            BitLocker encrypts your drive. If you proceed without suspending it first, the installer may not be able to resize partitions and your data could be at risk.
          </p>

          <ol className="space-y-3 list-decimal list-inside marker:text-slate-500">
            <li>
              Open <span className="font-medium text-slate-200">Settings</span> →{' '}
              <span className="font-medium text-slate-200">Privacy &amp; Security</span> →{' '}
              <span className="font-medium text-slate-200">Device encryption</span>.
            </li>
            <li>
              Click <span className="font-medium text-slate-200">Turn off</span> or{' '}
              <span className="font-medium text-slate-200">Suspend protection</span>.
            </li>
            <li>
              Wait for the decryption/suspension to complete (this may take a while depending on disk size).
            </li>
            <li>
              Return here and click <span className="font-medium text-slate-200">Re-check</span>.
            </li>
          </ol>

          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/20 text-amber-300 text-xs">
            <strong>Note:</strong> You can re-enable BitLocker after AltOS is installed if you wish.
          </div>
        </div>
      </GuidanceModal>
    </div>
  );
}
