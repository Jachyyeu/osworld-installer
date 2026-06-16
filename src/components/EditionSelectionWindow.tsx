import { useState, useEffect, useRef } from 'react';
import { Zap, Gamepad2, Palette, Shield, ArrowRight, ArrowLeft, CheckCircle, Settings2 } from 'lucide-react';
import { setEdition, setAppCustomization, writeTestState } from '../lib/tauri';

interface EditionSelectionWindowProps {
  onNext: () => void;
  onBack: () => void;
  autoplay?: boolean;
}

const EDITIONS = [
  {
    id: 'home',
    name: 'Home',
    subtitle: 'Free',
    price: 0,
    icon: <Zap className="w-5 h-5" />,
    description: 'Essential Linux desktop with core apps and utilities.',
    features: ['Web browser', 'Office suite', 'Media player', 'Email client'],
  },
  {
    id: 'gaming',
    name: 'Gaming',
    subtitle: 'Performance',
    price: 9.99,
    icon: <Gamepad2 className="w-5 h-5" />,
    description: 'Optimized for gaming with Steam, Proton, and GPU drivers.',
    features: ['Steam pre-installed', 'Proton GE', 'GameMode', 'MangoHud'],
  },
  {
    id: 'creative',
    name: 'Creative',
    subtitle: 'Pro',
    price: 14.99,
    icon: <Palette className="w-5 h-5" />,
    description: 'Creative workstation with design and video tools.',
    features: ['Blender', 'Krita', 'OBS Studio', 'DaVinci Resolve'],
  },
  {
    id: 'privacy',
    name: 'Privacy',
    subtitle: 'Secure',
    price: 9.99,
    icon: <Shield className="w-5 h-5" />,
    description: 'Hardened privacy-focused setup with encrypted defaults.',
    features: [' hardened Firefox', 'DNS-over-HTTPS', 'MAC randomization', 'VPN tools'],
  },
];

const BROWSERS = [
  { id: 'brave', name: 'Brave' },
  { id: 'chromium', name: 'Chromium' },
  { id: 'firefox', name: 'Firefox' },
];

const EMAIL_CLIENTS = [
  { id: 'thunderbird', name: 'Thunderbird' },
  { id: 'evolution', name: 'Evolution' },
  { id: 'geary', name: 'Geary' },
];

const MUSIC_PLAYERS = [
  { id: 'strawberry', name: 'Strawberry' },
  { id: 'rhythmbox', name: 'Rhythmbox' },
  { id: 'vlc', name: 'VLC' },
];

const TEST_STATE_PATH = 'C:\\altos-test-state.json';

export default function EditionSelectionWindow({ onNext, onBack, autoplay = false }: EditionSelectionWindowProps) {
  const [selectedEdition, setSelectedEdition] = useState<string | null>(null);
  const [showCustomize, setShowCustomize] = useState(false);
  const [browser, setBrowser] = useState('brave');
  const [emailClient, setEmailClient] = useState('thunderbird');
  const [musicPlayer, setMusicPlayer] = useState('strawberry');
  const [includeOfficeSuite, setIncludeOfficeSuite] = useState(true);
  const [isLoading, setIsLoading] = useState(false);

  const handleContinue = async () => {
    if (!selectedEdition) return;
    setIsLoading(true);
    const edition = EDITIONS.find((e) => e.id === selectedEdition);
    try {
      await setEdition(selectedEdition);
      await setAppCustomization(browser, emailClient, musicPlayer, includeOfficeSuite);
      await writeTestState(TEST_STATE_PATH, {
        screen: 'edition',
        edition: selectedEdition,
        price: edition?.price ?? 0,
        browser,
        emailClient,
        musicPlayer,
        includeOfficeSuite,
        timestamp: Date.now(),
      });
    } catch {
      // ignore test instrumentation errors
    }
    onNext();
  };

  const handleContinueRef = useRef(handleContinue);
  handleContinueRef.current = handleContinue;

  useEffect(() => {
    if (!autoplay) return;
    setSelectedEdition('home');
    const t = setTimeout(() => {
      handleContinueRef.current();
    }, 800);
    return () => clearTimeout(t);
  }, [autoplay]);

  const renderSelector = (
    label: string,
    options: { id: string; name: string }[],
    value: string,
    onChange: (id: string) => void
  ) => (
    <div className="space-y-2">
      <label className="text-xs font-medium text-altos-text-secondary uppercase tracking-wider">{label}</label>
      <div className="flex flex-wrap gap-2">
        {options.map((opt) => (
          <button
            key={opt.id}
            onClick={() => onChange(opt.id)}
            className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors ${
              value === opt.id
                ? 'bg-altos-blue text-white'
                : 'bg-[#1a1d21] text-altos-text-secondary hover:text-altos-text'
            }`}
          >
            {opt.name}
          </button>
        ))}
      </div>
    </div>
  );

  return (
    <div className="space-y-6">
      <div className="text-center space-y-1">
        <h2 className="text-xl font-semibold text-altos-text">Choose Your Edition</h2>
        <p className="text-sm text-altos-text-secondary">
          Select the AltOS flavor that fits your needs.
        </p>
      </div>

      <div className="grid gap-4">
        {EDITIONS.map((edition) => (
          <button
            key={edition.id}
            onClick={() => setSelectedEdition(edition.id)}
            className={`relative p-5 rounded-xl border text-left transition-all duration-150 ${
              selectedEdition === edition.id
                ? 'border-altos-blue bg-altos-blue-glow'
                : 'border-altos-border hover:border-[#3a3f47]'
            }`}
          >
            <div className="flex items-start gap-4">
              <div
                className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 transition-colors duration-150 ${
                  selectedEdition === edition.id ? 'bg-altos-blue' : 'bg-[#1a1d21]'
                }`}
              >
                <span className={selectedEdition === edition.id ? 'text-white' : 'text-altos-text-secondary'}>
                  {edition.icon}
                </span>
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between mb-1">
                  <div className="flex items-center gap-2">
                    <h3 className="text-base font-medium text-altos-text">{edition.name}</h3>
                    <span className="text-xs px-2 py-0.5 rounded-full bg-[#1a1d21] text-altos-text-secondary">
                      {edition.subtitle}
                    </span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium text-altos-text">
                      {edition.price === 0 ? 'Free' : `$${edition.price}`}
                    </span>
                    {selectedEdition === edition.id && (
                      <CheckCircle className="w-5 h-5 text-altos-blue flex-shrink-0" />
                    )}
                  </div>
                </div>
                <p className="text-sm text-altos-text-secondary mb-3">{edition.description}</p>
                <div className="flex flex-wrap gap-2">
                  {edition.features.map((feature) => (
                    <span
                      key={feature}
                      className="text-[11px] px-2 py-1 rounded-md bg-[#1a1d21] text-altos-text-secondary"
                    >
                      {feature}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          </button>
        ))}
      </div>

      <button
        onClick={() => setShowCustomize((s) => !s)}
        className="flex items-center gap-2 text-sm text-altos-text-secondary hover:text-altos-text transition-colors"
      >
        <Settings2 className="w-4 h-4" />
        {showCustomize ? 'Hide customization' : 'Customize default apps'}
      </button>

      {showCustomize && (
        <div className="bg-[#1a1d21] border border-altos-border rounded-xl p-4 space-y-4">
          {renderSelector('Web browser', BROWSERS, browser, setBrowser)}
          {renderSelector('Email client', EMAIL_CLIENTS, emailClient, setEmailClient)}
          {renderSelector('Music player', MUSIC_PLAYERS, musicPlayer, setMusicPlayer)}
          <label className="flex items-center gap-3 text-sm text-altos-text cursor-pointer">
            <input
              type="checkbox"
              checked={includeOfficeSuite}
              onChange={(e) => setIncludeOfficeSuite(e.target.checked)}
              className="w-4 h-4 rounded border-altos-border bg-altos-card text-altos-blue focus:ring-altos-blue"
            />
            Include LibreOffice with Windows-style skins
          </label>
        </div>
      )}

      <div className="flex justify-between pt-2">
        <button
          onClick={onBack}
          disabled={isLoading}
          className="flex items-center gap-2 px-5 py-2.5 rounded-lg font-medium text-altos-text-secondary hover:text-altos-text hover:bg-[#1a1d21] transition-colors duration-150 disabled:opacity-50"
        >
          <ArrowLeft className="w-5 h-5" />
          <span>Back</span>
        </button>

        <button
          onClick={handleContinue}
          disabled={!selectedEdition || isLoading}
          className={`flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white transition-colors duration-150 ${
            selectedEdition && !isLoading
              ? 'bg-altos-blue hover:bg-altos-blue-hover'
              : 'bg-[#3a3f47] cursor-not-allowed text-altos-text-secondary'
          }`}
        >
          {isLoading ? (
            <>
              <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
              </svg>
              <span>Loading...</span>
            </>
          ) : (
            <>
              <span>Continue</span>
              <ArrowRight className="w-5 h-5" />
            </>
          )}
        </button>
      </div>
    </div>
  );
}
