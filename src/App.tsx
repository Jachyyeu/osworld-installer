import { useState } from 'react';
import type { InstallType, InstallConfig } from './types';
import WelcomeWindow from './components/WelcomeWindow';
import SystemCheckWindow from './components/SystemCheckWindow';
import DiskSelectionWindow from './components/DiskSelectionWindow';
import UserSetupWindow from './components/UserSetupWindow';
import InstallationProgressWindow from './components/InstallationProgressWindow';
import UninstallerWindow from './components/UninstallerWindow';

type WindowStep = 'welcome' | 'systemcheck' | 'diskselection' | 'usersetup' | 'progress' | 'uninstaller';

function App() {
  const [currentStep, setCurrentStep] = useState<WindowStep>('welcome');
  const [installType, setInstallTypeState] = useState<InstallType | null>(null);
  const [, setConfig] = useState<InstallConfig>({});

  const handleInstallTypeSelect = (type: InstallType) => {
    setInstallTypeState(type);
    setConfig(prev => ({ ...prev, install_type: type }));
    setCurrentStep('systemcheck');
  };

  const handleSystemCheckComplete = () => {
    if (installType === 'dualboot') {
      setCurrentStep('diskselection');
    } else {
      setCurrentStep('usersetup');
    }
  };

  const handleDiskSelectionComplete = () => {
    setCurrentStep('usersetup');
  };

  const handleUserSetupComplete = () => {
    setCurrentStep('progress');
  };

  const handleBack = (step: WindowStep) => {
    setCurrentStep(step);
  };

  const handleOpenUninstaller = () => {
    setCurrentStep('uninstaller');
  };

  const renderCurrentWindow = () => {
    switch (currentStep) {
      case 'welcome':
        return <WelcomeWindow onSelect={handleInstallTypeSelect} />;
      case 'systemcheck':
        return (
          <SystemCheckWindow
            onNext={handleSystemCheckComplete}
            onBack={() => handleBack('welcome')}
          />
        );
      case 'diskselection':
        return (
          <DiskSelectionWindow
            onNext={handleDiskSelectionComplete}
            onBack={() => handleBack('systemcheck')}
          />
        );
      case 'usersetup':
        return (
          <UserSetupWindow
            onNext={handleUserSetupComplete}
            onBack={() => handleBack(installType === 'dualboot' ? 'diskselection' : 'systemcheck')}
          />
        );
      case 'progress':
        return <InstallationProgressWindow />;
      case 'uninstaller':
        return <UninstallerWindow onBack={() => setCurrentStep('welcome')} />;
      default:
        return <WelcomeWindow onSelect={handleInstallTypeSelect} />;
    }
  };

  const stepList = [
    { id: 'systemcheck', label: 'System Check' },
    ...(installType === 'dualboot' ? [{ id: 'diskselection', label: 'Disk Selection' }] : []),
    { id: 'usersetup', label: 'User Setup' },
  ];

  const activeStepIndex = stepList.findIndex(s => s.id === currentStep);

  return (
    <div className="min-h-screen bg-altos-bg flex items-start justify-center p-6">
      <div className="w-full max-w-2xl animate-fade-in">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 bg-altos-blue rounded-lg flex items-center justify-center transition-colors duration-150 hover:bg-altos-blue-hover">
              <svg className="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
              </svg>
            </div>
            <div>
              <h1 className="text-xl font-semibold text-altos-text leading-tight">AltOS Installer</h1>
              <p className="text-sm text-altos-text-secondary">Linux Distribution Installer</p>
            </div>
          </div>
          {currentStep === 'welcome' && (
            <button
              onClick={handleOpenUninstaller}
              className="text-xs text-altos-text-secondary hover:text-altos-danger transition-colors duration-150 underline"
            >
              Remove AltOS
            </button>
          )}
        </div>

        {/* Progress Indicator */}
        {currentStep !== 'welcome' && currentStep !== 'progress' && (
          <div className="bg-altos-card border border-altos-border rounded-xl px-6 py-4 mb-6">
            <div className="flex items-center">
              {stepList.map((step, index) => (
                <div key={step.id} className="flex items-center flex-1 last:flex-initial">
                  <div className="flex items-center gap-2">
                    <div className={`
                      w-7 h-7 rounded-full flex items-center justify-center text-xs font-medium transition-colors duration-150
                      ${currentStep === step.id
                        ? 'bg-altos-blue text-white'
                        : activeStepIndex > index
                          ? 'bg-altos-success text-white'
                          : 'bg-[#1e2127] text-altos-text-secondary'
                      }
                    `}>
                      {activeStepIndex > index ? (
                        <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
                        </svg>
                      ) : (
                        index + 1
                      )}
                    </div>
                    <span className={`
                      text-sm font-medium hidden sm:block transition-colors duration-150
                      ${currentStep === step.id ? 'text-altos-text' : 'text-altos-text-secondary'}
                    `}>
                      {step.label}
                    </span>
                  </div>
                  {index < stepList.length - 1 && (
                    <div className={`
                      flex-1 h-0.5 mx-3 rounded-full transition-colors duration-150
                      ${activeStepIndex > index ? 'bg-altos-success' : 'bg-[#1e2127]'}
                    `} />
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Content */}
        <div className="bg-altos-card border border-altos-border rounded-xl p-6">
          {renderCurrentWindow()}
        </div>
      </div>
    </div>
  );
}

export default App;
