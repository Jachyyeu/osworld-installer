import { useState, useEffect, useRef } from 'react';
import { 
  Download, 
  HardDrive, 
  Cog, 
  CheckCircle, 
  X,
  AlertTriangle,
  RotateCcw,
  Check
} from 'lucide-react';
import { startInstallation, cancelInstallation, onInstallProgress } from '../lib/tauri';
import type { InstallProgress } from '../types';

interface InstallStep {
  id: string;
  name: string;
  icon: React.ReactNode;
  status: 'pending' | 'in-progress' | 'completed' | 'error';
}

const INSTALL_STEPS: InstallStep[] = [
  { id: 'download', name: 'Downloading OS...', icon: <Download className="w-5 h-5" />, status: 'pending' },
  { id: 'prepare', name: 'Preparing Disk...', icon: <HardDrive className="w-5 h-5" />, status: 'pending' },
  { id: 'install', name: 'Installing System...', icon: <Cog className="w-5 h-5" />, status: 'pending' },
  { id: 'finalize', name: 'Finalizing...', icon: <CheckCircle className="w-5 h-5" />, status: 'pending' },
];

export default function InstallationProgressWindow() {
  const [steps, setSteps] = useState<InstallStep[]>(INSTALL_STEPS);
  const [overallProgress, setOverallProgress] = useState(0);
  const [currentStepName, setCurrentStepName] = useState('Starting installation...');
  const [isInstalling, setIsInstalling] = useState(true);
  const [isCompleted, setIsCompleted] = useState(false);
  const [showCancelDialog, setShowCancelDialog] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const unlistenRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    startListening();
    startInstall();

    return () => {
      if (unlistenRef.current) {
        unlistenRef.current();
      }
    };
  }, []);

  const startListening = async () => {
    try {
      const unlisten = await onInstallProgress((progress) => {
        updateProgress(progress);
      });
      unlistenRef.current = unlisten;
    } catch (err) {
      console.error('Failed to listen to progress:', err);
    }
  };

  const startInstall = async () => {
    try {
      await startInstallation();
      setIsCompleted(true);
      setIsInstalling(false);
      setCurrentStepName('Installation completed successfully!');
      setOverallProgress(100);
      
      // Mark all steps as completed
      setSteps(prev => prev.map(step => ({ ...step, status: 'completed' })));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Installation failed');
      setIsInstalling(false);
    }
  };

  const updateProgress = (progress: InstallProgress) => {
    setOverallProgress(progress.progress_percent);
    setCurrentStepName(progress.step);
    
    setSteps(prev => prev.map((step, index) => {
      if (index < progress.current_step_index) {
        return { ...step, status: 'completed' };
      } else if (index === progress.current_step_index) {
        return { ...step, status: 'in-progress' };
      }
      return { ...step, status: 'pending' };
    }));
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
    // In production, this would restart the application
    window.location.reload();
  };

  const handleFinish = () => {
    // In production, this would close the installer and reboot
    alert('System will now reboot to complete the installation.');
  };

  if (showCancelDialog) {
    return (
      <div className="space-y-6">
        <div className="bg-amber-50 border border-amber-200 rounded-lg p-6">
          <div className="flex items-start gap-4">
            <div className="w-12 h-12 bg-amber-100 rounded-full flex items-center justify-center flex-shrink-0">
              <AlertTriangle className="w-6 h-6 text-amber-600" />
            </div>
            <div>
              <h3 className="text-lg font-bold text-amber-800 mb-2">
                Cancel Installation?
              </h3>
              <p className="text-amber-700 mb-4">
                Cancelling the installation may leave your system in an inconsistent state. 
                We recommend letting the installation complete.
              </p>
              <div className="flex gap-3">
                <button
                  onClick={() => setShowCancelDialog(false)}
                  className="px-4 py-2 bg-white border border-amber-300 rounded-lg text-amber-700 font-medium hover:bg-amber-50 transition-colors"
                >
                  Continue Installation
                </button>
                <button
                  onClick={handleCancel}
                  className="px-4 py-2 bg-red-600 text-white rounded-lg font-medium hover:bg-red-700 transition-colors"
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
      <div className="text-center space-y-2">
        <h2 className="text-2xl font-bold text-slate-800">
          {isCompleted ? 'Installation Complete!' : 'Installing OSWorld'}
        </h2>
        <p className="text-slate-600">
          {isCompleted 
            ? 'Your system is ready. Please restart to complete the setup.'
            : 'Please do not turn off your computer during installation.'
          }
        </p>
      </div>

      {/* Error Message */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
            <div>
              <h4 className="font-semibold text-red-800 mb-1">Installation Failed</h4>
              <p className="text-sm text-red-700">{error}</p>
            </div>
          </div>
        </div>
      )}

      {/* Progress Section */}
      {!error && (
        <div className="space-y-6">
          {/* Overall Progress */}
          <div className="bg-slate-50 rounded-xl p-6">
            <div className="flex items-center justify-between mb-3">
              <span className="font-semibold text-slate-700">Overall Progress</span>
              <span className="text-2xl font-bold text-primary-600">{overallProgress}%</span>
            </div>
            
            {/* Progress Bar */}
            <div className="h-4 bg-slate-200 rounded-full overflow-hidden">
              <div 
                className={`
                  h-full rounded-full transition-all duration-500 animate-progress-pulse
                  ${isCompleted ? 'bg-green-500' : 'bg-gradient-to-r from-primary-500 to-primary-600'}
                `}
                style={{ width: `${overallProgress}%` }}
              />
            </div>
            
            {/* Current Step */}
            <div className="mt-4 flex items-center gap-3">
              {!isCompleted && isInstalling && (
                <svg className="animate-spin h-5 w-5 text-primary-600" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                </svg>
              )}
              {isCompleted && <CheckCircle className="w-5 h-5 text-green-500" />}
              <span className="text-slate-700 font-medium">{currentStepName}</span>
            </div>
          </div>

          {/* Steps List */}
          <div className="space-y-3">
            {steps.map((step, index) => (
              <div 
                key={step.id}
                className={`
                  flex items-center gap-4 p-4 rounded-lg border-2 transition-all duration-300
                  ${step.status === 'completed' 
                    ? 'bg-green-50 border-green-200' 
                    : step.status === 'in-progress'
                      ? 'bg-primary-50 border-primary-200'
                      : 'bg-slate-50 border-slate-100'
                  }
                `}
              >
                <div className={`
                  w-10 h-10 rounded-lg flex items-center justify-center
                  ${step.status === 'completed' 
                    ? 'bg-green-500 text-white' 
                    : step.status === 'in-progress'
                      ? 'bg-primary-500 text-white'
                      : 'bg-slate-200 text-slate-400'
                  }
                `}>
                  {step.status === 'completed' ? (
                    <Check className="w-5 h-5" />
                  ) : (
                    step.icon
                  )}
                </div>
                
                <div className="flex-1">
                  <p className={`
                    font-medium
                    ${step.status === 'completed' 
                      ? 'text-green-800' 
                      : step.status === 'in-progress'
                        ? 'text-primary-800'
                        : 'text-slate-500'
                    }
                  `}>
                    {step.name}
                  </p>
                </div>
                
                <div className="flex-shrink-0">
                  {step.status === 'in-progress' && (
                    <svg className="animate-spin h-5 w-5 text-primary-600" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                    </svg>
                  )}
                  {step.status === 'completed' && (
                    <CheckCircle className="w-5 h-5 text-green-500" />
                  )}
                  {step.status === 'pending' && (
                    <div className="w-5 h-5 rounded-full border-2 border-slate-300" />
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Action Buttons */}
      <div className="flex justify-center gap-4 pt-4">
        {isInstalling && !isCompleted && (
          <button
            onClick={() => setShowCancelDialog(true)}
            className="flex items-center gap-2 px-6 py-3 rounded-lg font-semibold text-red-600
              bg-red-50 hover:bg-red-100 transition-colors"
          >
            <X className="w-5 h-5" />
            <span>Cancel Installation</span>
          </button>
        )}

        {error && (
          <button
            onClick={handleRestart}
            className="flex items-center gap-2 px-8 py-3 rounded-lg font-semibold text-white
              bg-primary-600 hover:bg-primary-700 shadow-lg hover:shadow-xl transition-all"
          >
            <RotateCcw className="w-5 h-5" />
            <span>Restart Installer</span>
          </button>
        )}

        {isCompleted && (
          <button
            onClick={handleFinish}
            className="flex items-center gap-2 px-8 py-3 rounded-lg font-semibold text-white
              bg-green-600 hover:bg-green-700 shadow-lg hover:shadow-xl transition-all"
          >
            <Check className="w-5 h-5" />
            <span>Finish & Reboot</span>
          </button>
        )}
      </div>

      {/* Tips */}
      {!isCompleted && !error && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div className="flex items-start gap-3">
            <div className="w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center flex-shrink-0">
              <span className="text-blue-600 font-bold text-sm">?</span>
            </div>
            <div>
              <h4 className="font-semibold text-blue-800 mb-1">Installation Tips</h4>
              <ul className="text-sm text-blue-700 space-y-1">
                <li>• Keep your computer plugged in during installation</li>
                <li>• The installation may take 15-30 minutes depending on your system</li>
                <li>• Your computer will restart automatically when complete</li>
              </ul>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
