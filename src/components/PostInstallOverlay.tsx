import { useState, useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Leaf,
  Monitor,
  Keyboard,
  FolderOpen,
  Download,
  Image as ImageIcon,
  FileText,
  ShoppingBag,
  Gamepad2,
  Globe,
  Code2,
  MessageCircle,
  Check,
  ChevronRight,
  ChevronLeft,
  X,
} from 'lucide-react';
import { invoke } from '@tauri-apps/api/core';

interface PostInstallOverlayProps {
  onDismiss?: () => void;
  onOpenWizard?: () => void;
}

// ==================== Slide Data ====================

interface SlideData {
  id: string;
  title: string;
  subtitle: string;
  illustration: React.ReactNode;
}

// ==================== Sub-components ====================

function DesktopMockup() {
  return (
    <div className="relative w-full max-w-2xl mx-auto aspect-video rounded-2xl overflow-hidden shadow-2xl border border-slate-700/50 bg-gradient-to-br from-slate-800 to-slate-900">
      {/* Wallpaper */}
      <div className="absolute inset-0 bg-gradient-to-br from-indigo-900/40 via-slate-900 to-emerald-900/30" />
      {/* Top panel */}
      <div className="absolute top-0 left-0 right-0 h-8 bg-slate-900/80 backdrop-blur flex items-center px-3 gap-3">
        <div className="flex gap-1.5">
          <div className="w-2.5 h-2.5 rounded-full bg-rose-500/80" />
          <div className="w-2.5 h-2.5 rounded-full bg-amber-500/80" />
          <div className="w-2.5 h-2.5 rounded-full bg-emerald-500/80" />
        </div>
        <div className="flex-1 text-center text-[10px] text-slate-400 font-medium">AltOS Desktop</div>
      </div>
      {/* Desktop icons */}
      <div className="absolute top-14 left-4 flex flex-col gap-4">
        {['Home', 'Files', 'Web', 'Store'].map((label, i) => (
          <div key={label} className="flex flex-col items-center gap-1">
            <div className={`w-10 h-10 rounded-xl flex items-center justify-center ${
              i === 0 ? 'bg-blue-500/20 text-blue-400' :
              i === 1 ? 'bg-amber-500/20 text-amber-400' :
              i === 2 ? 'bg-orange-500/20 text-orange-400' :
              'bg-emerald-500/20 text-emerald-400'
            }`}>
              {i === 0 ? <Monitor className="w-5 h-5" /> :
               i === 1 ? <FolderOpen className="w-5 h-5" /> :
               i === 2 ? <Globe className="w-5 h-5" /> :
               <ShoppingBag className="w-5 h-5" />}
            </div>
            <span className="text-[9px] text-slate-400">{label}</span>
          </div>
        ))}
      </div>
      {/* Center logo */}
      <div className="absolute inset-0 flex items-center justify-center">
        <motion.div
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.3, duration: 0.6 }}
          className="w-24 h-24 rounded-3xl bg-gradient-to-br from-emerald-500/20 to-blue-500/20 border border-emerald-500/30 flex items-center justify-center backdrop-blur"
        >
          <Leaf className="w-12 h-12 text-emerald-400" />
        </motion.div>
      </div>
    </div>
  );
}

function LauncherMockup() {
  const [pressed, setPressed] = useState(false);

  useEffect(() => {
    const interval = setInterval(() => {
      setPressed((p) => !p);
    }, 2200);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="relative w-full max-w-lg mx-auto aspect-video">
      {/* Keyboard key */}
      <motion.div
        className="absolute left-8 top-1/2 -translate-y-1/2"
        animate={{ y: pressed ? -4 : 0, scale: pressed ? 0.95 : 1 }}
        transition={{ duration: 0.2 }}
      >
        <div className={`w-20 h-20 rounded-2xl flex flex-col items-center justify-center border-2 transition-colors duration-300 ${
          pressed ? 'bg-slate-700 border-emerald-500/60 shadow-[0_0_20px_rgba(52,211,153,0.3)]' : 'bg-slate-800 border-slate-600'
        }`}>
          <Keyboard className={`w-8 h-8 transition-colors duration-300 ${pressed ? 'text-emerald-400' : 'text-slate-400'}`} />
          <span className="text-[9px] mt-1 text-slate-500 font-medium">Super</span>
        </div>
      </motion.div>

      {/* Arrow */}
      <motion.div
        className="absolute left-32 top-1/2 -translate-y-1/2"
        animate={{ opacity: pressed ? 1 : 0.3, x: pressed ? 4 : 0 }}
        transition={{ duration: 0.3 }}
      >
        <ChevronRight className="w-8 h-8 text-emerald-400" />
      </motion.div>

      {/* Launcher */}
      <motion.div
        className="absolute right-8 top-1/2 -translate-y-1/2"
        initial={{ opacity: 0, scale: 0.9, x: 20 }}
        animate={{
          opacity: pressed ? 1 : 0,
          scale: pressed ? 1 : 0.9,
          x: pressed ? 0 : 20,
        }}
        transition={{ duration: 0.35, ease: 'easeOut' }}
      >
        <div className="w-56 rounded-2xl bg-slate-800/95 border border-slate-700 shadow-2xl backdrop-blur overflow-hidden">
          <div className="p-3 border-b border-slate-700">
            <div className="h-8 rounded-lg bg-slate-700/50 flex items-center px-3 text-xs text-slate-500">Search apps…</div>
          </div>
          <div className="p-3 grid grid-cols-4 gap-3">
            {['Files', 'Web', 'Term', 'Store', 'Music', 'Video', 'Settings', 'More'].map((app, i) => (
              <div key={app} className="flex flex-col items-center gap-1">
                <div className={`w-10 h-10 rounded-xl flex items-center justify-center ${
                  i % 3 === 0 ? 'bg-blue-500/20 text-blue-400' :
                  i % 3 === 1 ? 'bg-emerald-500/20 text-emerald-400' :
                  'bg-amber-500/20 text-amber-400'
                }`}>
                  <span className="text-xs font-bold">{app[0]}</span>
                </div>
                <span className="text-[9px] text-slate-400">{app}</span>
              </div>
            ))}
          </div>
        </div>
      </motion.div>
    </div>
  );
}

function FilesMockup() {
  return (
    <div className="relative w-full max-w-xl mx-auto aspect-video rounded-2xl overflow-hidden shadow-2xl border border-slate-700/50 bg-slate-800/90 backdrop-blur">
      {/* Title bar */}
      <div className="h-9 bg-slate-900/80 flex items-center px-3 gap-2 border-b border-slate-700">
        <div className="flex gap-1.5">
          <div className="w-2.5 h-2.5 rounded-full bg-rose-500/80" />
          <div className="w-2.5 h-2.5 rounded-full bg-amber-500/80" />
          <div className="w-2.5 h-2.5 rounded-full bg-emerald-500/80" />
        </div>
        <FolderOpen className="w-4 h-4 text-amber-400 ml-2" />
        <span className="text-xs text-slate-300 font-medium">Dolphin — Windows</span>
      </div>
      {/* Sidebar */}
      <div className="absolute left-0 top-9 bottom-0 w-36 bg-slate-900/50 border-r border-slate-700 p-3 space-y-2">
        {['Home', 'Documents', 'Downloads', 'Pictures', 'Windows'].map((item) => (
          <div key={item} className={`flex items-center gap-2 px-2 py-1.5 rounded-lg text-xs ${
            item === 'Windows' ? 'bg-blue-500/10 text-blue-400 font-medium' : 'text-slate-400'
          }`}>
            {item === 'Windows' ? <Monitor className="w-3.5 h-3.5" /> :
             item === 'Documents' ? <FileText className="w-3.5 h-3.5" /> :
             item === 'Pictures' ? <ImageIcon className="w-3.5 h-3.5" /> :
             item === 'Downloads' ? <Download className="w-3.5 h-3.5" /> :
             <FolderOpen className="w-3.5 h-3.5" />}
            {item}
          </div>
        ))}
      </div>
      {/* File grid */}
      <div className="absolute left-36 top-9 right-0 bottom-0 p-4 grid grid-cols-4 gap-4">
        {[
          { name: 'Documents', icon: <FileText className="w-6 h-6" />, color: 'text-blue-400 bg-blue-500/15' },
          { name: 'Pictures', icon: <ImageIcon className="w-6 h-6" />, color: 'text-purple-400 bg-purple-500/15' },
          { name: 'Downloads', icon: <Download className="w-6 h-6" />, color: 'text-emerald-400 bg-emerald-500/15' },
          { name: 'Music', icon: <ShoppingBag className="w-6 h-6" />, color: 'text-rose-400 bg-rose-500/15' },
        ].map((folder) => (
          <div key={folder.name} className="flex flex-col items-center gap-2 p-3 rounded-xl hover:bg-slate-700/30 transition-colors">
            <div className={`w-12 h-12 rounded-xl flex items-center justify-center ${folder.color}`}>
              {folder.icon}
            </div>
            <span className="text-[10px] text-slate-300 text-center">{folder.name}</span>
          </div>
        ))}
      </div>
      {/* Highlight badge */}
      <motion.div
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.5 }}
        className="absolute bottom-4 left-40 right-4"
      >
        <div className="bg-blue-500/10 border border-blue-500/20 rounded-lg px-3 py-2 flex items-center gap-2">
          <Monitor className="w-4 h-4 text-blue-400" />
          <span className="text-xs text-blue-300">Your Windows files are safely mounted here</span>
        </div>
      </motion.div>
    </div>
  );
}

function StoreMockup() {
  const apps = [
    { name: 'Steam', icon: <Gamepad2 className="w-7 h-7" />, color: 'from-blue-600 to-slate-700' },
    { name: 'Firefox', icon: <Globe className="w-7 h-7" />, color: 'from-orange-500 to-orange-700' },
    { name: 'VS Code', icon: <Code2 className="w-7 h-7" />, color: 'from-blue-500 to-blue-700' },
    { name: 'Discord', icon: <MessageCircle className="w-7 h-7" />, color: 'from-indigo-500 to-indigo-700' },
  ];

  return (
    <div className="relative w-full max-w-lg mx-auto">
      {/* Search bar */}
      <div className="mb-4 h-10 rounded-xl bg-slate-800 border border-slate-700 flex items-center px-4 gap-2">
        <ShoppingBag className="w-4 h-4 text-slate-500" />
        <span className="text-sm text-slate-500">Search apps…</span>
      </div>
      {/* App grid */}
      <div className="grid grid-cols-2 gap-3">
        {apps.map((app, i) => (
          <motion.div
            key={app.name}
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 + i * 0.1 }}
            className="p-4 rounded-2xl bg-gradient-to-br from-slate-800 to-slate-900 border border-slate-700/50 flex items-center gap-3 hover:border-slate-600 transition-colors"
          >
            <div className={`w-12 h-12 rounded-xl bg-gradient-to-br ${app.color} flex items-center justify-center text-white shadow-lg`}>
              {app.icon}
            </div>
            <div>
              <p className="text-sm font-medium text-slate-200">{app.name}</p>
              <p className="text-[10px] text-slate-500">One-click install</p>
            </div>
          </motion.div>
        ))}
      </div>
    </div>
  );
}

function BootMenuMockup({ altosDefault, onToggle }: { altosDefault: boolean; onToggle: () => void }) {
  return (
    <div className="relative w-full max-w-md mx-auto">
      {/* rEFInd mockup */}
      <div className="rounded-2xl bg-slate-900 border border-slate-700 shadow-2xl overflow-hidden">
        <div className="p-6 space-y-4">
          <p className="text-center text-xs text-slate-500 uppercase tracking-widest font-medium">Boot Menu</p>

          {/* AltOS entry */}
          <motion.div
            animate={{
              borderColor: altosDefault ? 'rgba(52,211,153,0.4)' : 'rgba(51,65,85,0.5)',
              backgroundColor: altosDefault ? 'rgba(52,211,153,0.08)' : 'rgba(30,41,59,0.3)',
            }}
            className="flex items-center gap-4 p-4 rounded-xl border-2"
          >
            <div className="w-12 h-12 rounded-xl bg-emerald-500/20 flex items-center justify-center">
              <Leaf className="w-6 h-6 text-emerald-400" />
            </div>
            <div className="flex-1">
              <p className="text-sm font-semibold text-slate-100">AltOS</p>
              <p className="text-xs text-slate-500">Linux</p>
            </div>
            {altosDefault && (
              <motion.div
                initial={{ scale: 0 }}
                animate={{ scale: 1 }}
                className="px-2 py-1 rounded-full bg-emerald-500/20 text-emerald-400 text-[10px] font-bold"
              >
                DEFAULT
              </motion.div>
            )}
          </motion.div>

          {/* Windows entry */}
          <motion.div
            animate={{
              borderColor: !altosDefault ? 'rgba(59,130,246,0.4)' : 'rgba(51,65,85,0.5)',
              backgroundColor: !altosDefault ? 'rgba(59,130,246,0.08)' : 'rgba(30,41,59,0.3)',
            }}
            className="flex items-center gap-4 p-4 rounded-xl border-2"
          >
            <div className="w-12 h-12 rounded-xl bg-blue-500/20 flex items-center justify-center">
              <Monitor className="w-6 h-6 text-blue-400" />
            </div>
            <div className="flex-1">
              <p className="text-sm font-semibold text-slate-100">Windows</p>
              <p className="text-xs text-slate-500">Microsoft Windows</p>
            </div>
            {!altosDefault && (
              <motion.div
                initial={{ scale: 0 }}
                animate={{ scale: 1 }}
                className="px-2 py-1 rounded-full bg-blue-500/20 text-blue-400 text-[10px] font-bold"
              >
                DEFAULT
              </motion.div>
            )}
          </motion.div>
        </div>
      </div>

      {/* Toggle */}
      <div className="mt-6 flex items-center justify-center gap-3">
        <span className="text-sm text-slate-400">Set AltOS as default?</span>
        <button
          onClick={onToggle}
          className={`relative w-12 h-7 rounded-full p-1 transition-colors duration-200 ${
            altosDefault ? 'bg-emerald-500' : 'bg-slate-700'
          }`}
        >
          <motion.div
            animate={{ x: altosDefault ? 20 : 0 }}
            transition={{ type: 'spring', stiffness: 500, damping: 30 }}
            className="w-5 h-5 rounded-full bg-white shadow-sm"
          />
        </button>
      </div>
    </div>
  );
}

// ==================== Main Overlay ====================

export default function PostInstallOverlay({ onDismiss, onOpenWizard }: PostInstallOverlayProps) {
  const [slide, setSlide] = useState(0);
  const [direction, setDirection] = useState(0);
  const [altosDefault, setAltosDefault] = useState(true);
  const [visible, setVisible] = useState(true);

  const slides: SlideData[] = [
    {
      id: 'welcome',
      title: 'Welcome to AltOS',
      subtitle: "Let's get you set up in under 2 minutes",
      illustration: <DesktopMockup />,
    },
    {
      id: 'launcher',
      title: 'Everything you need, one press away',
      subtitle: 'Press the Windows / Super key to open your apps',
      illustration: <LauncherMockup />,
    },
    {
      id: 'files',
      title: 'Your Windows files are right here',
      subtitle: "Your Documents, Pictures, and Downloads from Windows are in the 'Windows' folder",
      illustration: <FilesMockup />,
    },
    {
      id: 'apps',
      title: 'Install apps without the terminal',
      subtitle: 'Browse, search, and install apps with one click',
      illustration: <StoreMockup />,
    },
    {
      id: 'dualboot',
      title: 'Switching between Windows and AltOS',
      subtitle: "When your PC starts, pick Windows or AltOS. You're always in control.",
      illustration: <BootMenuMockup altosDefault={altosDefault} onToggle={() => setAltosDefault((v) => !v)} />,
    },
  ];

  const current = slides[slide];
  const isFirst = slide === 0;
  const isLast = slide === slides.length - 1;

  const goNext = useCallback(() => {
    if (isLast) {
      handleFinish();
    } else {
      setDirection(1);
      setSlide((s) => Math.min(s + 1, slides.length - 1));
    }
  }, [isLast]);

  const goBack = useCallback(() => {
    setDirection(-1);
    setSlide((s) => Math.max(s - 1, 0));
  }, []);

  const handleSkip = useCallback(async () => {
    try {
      await invoke('mark_post_install_seen');
    } catch {
      // Fallback: the host app should handle persistence
    }
    setVisible(false);
    setTimeout(() => onDismiss?.(), 400);
  }, [onDismiss]);

  const handleFinish = useCallback(async () => {
    try {
      await invoke('set_refind_default', { enabled: altosDefault });
      await invoke('mark_post_install_seen');
    } catch {
      // Commands may not be registered yet; host app handles this
    }
    setVisible(false);
    setTimeout(() => {
      onDismiss?.();
      onOpenWizard?.();
    }, 400);
  }, [altosDefault, onDismiss, onOpenWizard]);

  // Keyboard navigation
  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight') goNext();
      if (e.key === 'ArrowLeft') goBack();
      if (e.key === 'Escape') handleSkip();
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [goNext, goBack, handleSkip]);

  const variants = {
    enter: (dir: number) => ({ x: dir > 0 ? 80 : -80, opacity: 0 }),
    center: { x: 0, opacity: 1 },
    exit: (dir: number) => ({ x: dir > 0 ? -80 : 80, opacity: 0 }),
  };

  if (!visible) return null;

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.4 }}
      className="fixed inset-0 z-[100] bg-gradient-to-br from-slate-950 via-slate-900 to-slate-950 flex flex-col"
    >
      {/* Skip button */}
      <div className="absolute top-6 right-6 z-10">
        <button
          onClick={handleSkip}
          className="flex items-center gap-1.5 px-4 py-2 rounded-full text-sm text-slate-400 hover:text-slate-200 hover:bg-slate-800/60 transition-colors"
        >
          <X className="w-4 h-4" />
          Skip tour
        </button>
      </div>

      {/* Logo watermark */}
      <div className="absolute top-6 left-6 flex items-center gap-2 opacity-40">
        <Leaf className="w-5 h-5 text-emerald-400" />
        <span className="text-sm font-semibold text-slate-300">AltOS</span>
      </div>

      {/* Main content */}
      <div className="flex-1 flex flex-col lg:flex-row overflow-hidden">
        {/* Illustration area (~60%) */}
        <div className="flex-1 lg:flex-[1.4] flex items-center justify-center p-8 lg:p-12 relative">
          <div className="absolute inset-0 bg-gradient-to-b from-emerald-500/5 to-transparent pointer-events-none" />
          <AnimatePresence mode="wait" custom={direction}>
            <motion.div
              key={current.id}
              custom={direction}
              variants={variants}
              initial="enter"
              animate="center"
              exit="exit"
              transition={{ duration: 0.35, ease: 'easeInOut' }}
              className="w-full"
            >
              {current.illustration}
            </motion.div>
          </AnimatePresence>
        </div>

        {/* Text area (~40%) */}
        <div className="flex-1 lg:flex-[1] flex flex-col justify-center p-8 lg:p-12 lg:pr-16 relative">
          <div className="absolute inset-y-0 left-0 w-px bg-gradient-to-b from-transparent via-slate-700/50 to-transparent hidden lg:block" />

          <AnimatePresence mode="wait" custom={direction}>
            <motion.div
              key={current.id}
              custom={direction}
              variants={variants}
              initial="enter"
              animate="center"
              exit="exit"
              transition={{ duration: 0.35, ease: 'easeInOut' }}
              className="space-y-6"
            >
              {/* Slide number */}
              <div className="flex items-center gap-2">
                <span className="text-xs font-bold text-emerald-400 uppercase tracking-widest">
                  Step {slide + 1} of {slides.length}
                </span>
                <div className="h-px flex-1 bg-slate-800" />
              </div>

              {/* Title */}
              <h1 className="text-3xl lg:text-4xl font-bold text-slate-100 leading-tight">
                {current.title}
              </h1>

              {/* Subtitle */}
              <p className="text-base lg:text-lg text-slate-400 leading-relaxed max-w-md">
                {current.subtitle}
              </p>

              {/* Navigation */}
              <div className="pt-4 flex items-center gap-4">
                {!isFirst && (
                  <motion.button
                    initial={{ opacity: 0, x: -10 }}
                    animate={{ opacity: 1, x: 0 }}
                    onClick={goBack}
                    className="flex items-center gap-2 px-5 py-2.5 rounded-full border border-slate-700 text-sm font-medium text-slate-300 hover:bg-slate-800 hover:border-slate-600 transition-colors"
                  >
                    <ChevronLeft className="w-4 h-4" />
                    Back
                  </motion.button>
                )}

                <motion.button
                  whileHover={{ scale: 1.03 }}
                  whileTap={{ scale: 0.97 }}
                  onClick={goNext}
                  className={`flex items-center gap-2 px-6 py-2.5 rounded-full text-sm font-medium transition-colors ${
                    isLast
                      ? 'bg-emerald-500 text-white hover:bg-emerald-400 shadow-lg shadow-emerald-500/20'
                      : 'bg-slate-100 text-slate-900 hover:bg-white'
                  }`}
                >
                  {isLast ? (
                    <>
                      <Check className="w-4 h-4" />
                      Get Started
                    </>
                  ) : (
                    <>
                      Next
                      <ChevronRight className="w-4 h-4" />
                    </>
                  )}
                </motion.button>
              </div>
            </motion.div>
          </AnimatePresence>

          {/* Dot indicators */}
          <div className="flex items-center gap-2 mt-10">
            {slides.map((s, i) => (
              <button
                key={s.id}
                onClick={() => {
                  setDirection(i > slide ? 1 : -1);
                  setSlide(i);
                }}
                className="group relative p-1"
              >
                <div
                  className={`w-2.5 h-2.5 rounded-full transition-all duration-300 ${
                    i === slide ? 'bg-emerald-400 scale-110' : 'bg-slate-700 group-hover:bg-slate-600'
                  }`}
                />
                {i === slide && (
                  <motion.div
                    layoutId="activeDot"
                    className="absolute inset-0 rounded-full border-2 border-emerald-400/30"
                    transition={{ type: 'spring', stiffness: 300, damping: 25 }}
                  />
                )}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Bottom gradient fade */}
      <div className="h-16 bg-gradient-to-t from-slate-950 to-transparent pointer-events-none" />
    </motion.div>
  );
}
