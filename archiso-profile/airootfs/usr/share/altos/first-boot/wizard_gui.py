#!/usr/bin/env python3
"""
AltOS First-Boot Wizard — PyQt6 GUI
Replaces the terminal-based wizard.sh with a premium visual experience.
"""

import os
import sys
import subprocess
import shutil
from pathlib import Path

from PyQt6.QtCore import (
    Qt, QPropertyAnimation, QEasingCurve, QPoint, QProcess,
    QThread, pyqtSignal, QSize
)
from PyQt6.QtGui import QFont, QFontDatabase, QColor, QPainter, QBrush, QPen
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QStackedWidget, QGraphicsDropShadowEffect,
    QProgressBar, QScrollArea, QFrame, QSizePolicy, QFileDialog
)

# ============================================================
# Constants
# ============================================================

DONE_FLAG = Path.home() / ".config" / "altos" / "first-boot-done"
STEPS_DIR = Path(__file__).parent / "steps"

THEMES = [
    {
        "id": "win11",
        "name": "Windows 11 Style",
        "desc": "Familiar and comfortable",
        "gradient": "linear-gradient(135deg, #3b82f6 0%, #1e40af 100%)",
        "accent": "#3b82f6",
        "preview_shape": "rounded-rect",
    },
    {
        "id": "clean",
        "name": "Clean Modern",
        "desc": "Minimal and fast",
        "gradient": "linear-gradient(135deg, #64748b 0%, #334155 100%)",
        "accent": "#64748b",
        "preview_shape": "circle",
    },
    {
        "id": "dark",
        "name": "Dark Pro",
        "desc": "Easy on the eyes",
        "gradient": "linear-gradient(135deg, #0f172a 0%, #1e293b 100%)",
        "accent": "#10b981",
        "preview_shape": "rounded-rect",
    },
]

APPS = [
    {"name": "Steam", "pkg": "steam", "flatpak": "com.valvesoftware.Steam", "icon": "S", "color": "#1b2838", "desc": "Your games library"},
    {"name": "Discord", "pkg": "discord", "flatpak": "com.discordapp.Discord", "icon": "D", "color": "#5865F2", "desc": "Chat with friends"},
    {"name": "Spotify", "pkg": "spotify-launcher", "flatpak": "com.spotify.Client", "icon": "S", "color": "#1DB954", "desc": "Music streaming"},
    {"name": "VS Code", "pkg": "code", "flatpak": "com.visualstudio.code", "icon": "C", "color": "#007ACC", "desc": "Code editor"},
    {"name": "Chrome", "pkg": "google-chrome", "flatpak": "com.google.Chrome", "icon": "C", "color": "#EA4335", "desc": "Web browser"},
]

IMPORT_ITEMS = [
    {"key": "documents", "label": "Documents", "checked": True},
    {"key": "pictures", "label": "Pictures", "checked": True},
    {"key": "desktop", "label": "Desktop files", "checked": True},
    {"key": "bookmarks", "label": "Browser bookmarks", "checked": True},
    {"key": "wifi", "label": "WiFi passwords", "checked": True},
]


def _kwrite_bin():
    """Return the available KDE config tool (Plasma 6 preferred, fallback to Plasma 5)."""
    for binary in ("kwriteconfig6", "kwriteconfig5"):
        if shutil.which(binary):
            return binary
    return None


def _kstart_bin():
    """Return the available kstart tool for restarting Plasma."""
    for binary in ("kstart", "kstart5"):
        if shutil.which(binary):
            return binary
    return None


# ============================================================
# Worker threads
# ============================================================

class ThemeApplyWorker(QThread):
    finished = pyqtSignal(bool, str)

    def __init__(self, theme_id):
        super().__init__()
        self.theme_id = theme_id

    def run(self):
        try:
            script = STEPS_DIR / "pick-theme.sh"
            # The bash script is interactive; we need to feed it the choice.
            # We'll replicate the kwriteconfig5 calls directly.
            self._apply_theme(self.theme_id)
            self.finished.emit(True, f"{self.theme_id.capitalize()} theme applied")
        except Exception as e:
            self.finished.emit(False, str(e))

    def _apply_theme(self, theme_id):
        themes_dir = Path("/usr/share/altos/themes")
        theme_path = themes_dir / theme_id
        kde_config = Path.home() / ".config"
        kde_config.mkdir(parents=True, exist_ok=True)

        if theme_path.exists():
            config_src = theme_path / "config"
            if config_src.exists():
                for item in config_src.iterdir():
                    if item.is_dir():
                        dst = kde_config / item.name
                        if dst.exists():
                            shutil.copytree(item, dst, dirs_exist_ok=True)
                        else:
                            shutil.copytree(item, dst)
                    else:
                        shutil.copy2(item, kde_config / item.name)
            apply_script = theme_path / "apply.sh"
            if apply_script.exists():
                subprocess.run([str(apply_script)], check=False)

        # Theme-specific tweaks
        kwrite = _kwrite_bin()
        if kwrite:
            if theme_id == "win11":
                subprocess.run([kwrite, "--file", "kwinrc", "--group", "TabBox", "--key", "LayoutName", "thumbnail_grid"], check=False)
                subprocess.run([kwrite, "--file", "kcmfonts", "--group", "General", "--key", "font", "Segoe UI,10,-1,5,50,0,0,0,0,0"], check=False)
            elif theme_id == "dark":
                subprocess.run([kwrite, "--file", "kdeglobals", "--group", "General", "--key", "ColorScheme", "BreezeDark"], check=False)
                subprocess.run([kwrite, "--file", "kcmfonts", "--group", "General", "--key", "XftAntialias", "true"], check=False)

        # Restart Plasma if running
        try:
            subprocess.run(["pgrep", "plasmashell"], check=True, stdout=subprocess.DEVNULL)
            kstart = _kstart_bin()
            if kstart:
                subprocess.Popen([kstart, "plasmashell"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            pass


class AppInstallWorker(QThread):
    progress = pyqtSignal(str, int)  # name, percent
    finished = pyqtSignal(str, bool, str)  # name, success, message

    def __init__(self, app_info):
        super().__init__()
        self.app_info = app_info

    def run(self):
        name = self.app_info["name"]
        pkg = self.app_info["pkg"]
        flatpak = self.app_info["flatpak"]

        self.progress.emit(name, 10)

        # Check if already installed
        if shutil.which(pkg) or self._pacman_qi(pkg):
            self.finished.emit(name, True, "Already installed")
            return

        self.progress.emit(name, 30)

        # Try pacman
        if self._pacman_si(pkg):
            self.progress.emit(name, 50)
            result = subprocess.run(
                ["sudo", "pacman", "-S", "--noconfirm", "--needed", pkg],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                self.finished.emit(name, True, "Installed via pacman")
                return

        self.progress.emit(name, 70)

        # Try flatpak
        if shutil.which("flatpak"):
            result = subprocess.run(
                ["flatpak", "install", "--noninteractive", "flathub", flatpak],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                self.finished.emit(name, True, "Installed via Flatpak")
                return

        self.finished.emit(name, False, "Could not install automatically")

    @staticmethod
    def _pacman_qi(pkg):
        return subprocess.run(["pacman", "-Qi", pkg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

    @staticmethod
    def _pacman_si(pkg):
        return subprocess.run(["pacman", "-Si", pkg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


class ImportWorker(QThread):
    progress = pyqtSignal(str, int)
    finished = pyqtSignal(bool, str)

    def __init__(self, items, windows_part, win_user_dir):
        super().__init__()
        self.items = items
        self.windows_part = windows_part
        self.win_user_dir = win_user_dir

    def run(self):
        mount_point = "/tmp/windows_import_gui"
        import_dest = Path.home() / "windows-migration"
        import_dest.mkdir(parents=True, exist_ok=True)

        try:
            subprocess.run(["mkdir", "-p", mount_point], check=True)
            subprocess.run(["sudo", "mount", "-o", "ro", self.windows_part, mount_point], check=True)
        except subprocess.CalledProcessError:
            self.finished.emit(False, "Could not mount Windows partition")
            return

        total = len(self.items)
        for idx, item in enumerate(self.items):
            pct = int(((idx + 1) / total) * 100)
            self.progress.emit(item["label"], pct)

            try:
                self._import_item(item["key"], mount_point, import_dest)
            except Exception as e:
                print(f"Import error for {item['key']}: {e}")

        subprocess.run(["sudo", "umount", mount_point], check=False)
        subprocess.run(["sudo", "chown", "-R", f"{os.getuid()}:{os.getgid()}", str(import_dest)], check=False)
        self.finished.emit(True, f"Imported to {import_dest}")

    def _import_item(self, key, mount_point, import_dest):
        user_dir = self.win_user_dir

        if key == "documents":
            src = Path(user_dir) / "Documents"
            if src.exists():
                dst = import_dest / "Documents"
                shutil.copytree(src, dst, dirs_exist_ok=True)
        elif key == "pictures":
            src = Path(user_dir) / "Pictures"
            if src.exists():
                dst = import_dest / "Pictures"
                shutil.copytree(src, dst, dirs_exist_ok=True)
        elif key == "desktop":
            src = Path(user_dir) / "Desktop"
            if src.exists():
                dst = import_dest / "Desktop"
                shutil.copytree(src, dst, dirs_exist_ok=True)
        elif key == "bookmarks":
            bm_dir = import_dest / "bookmarks"
            bm_dir.mkdir(exist_ok=True)
            # Firefox
            ff_src = Path(user_dir) / "AppData" / "Roaming" / "Mozilla" / "Firefox" / "Profiles"
            if ff_src.exists():
                for places in ff_src.rglob("places.sqlite"):
                    shutil.copy2(places, bm_dir / "firefox_places.sqlite")
            # Chrome
            chrome_src = Path(user_dir) / "AppData" / "Local" / "Google" / "Chrome" / "User Data" / "Default" / "Bookmarks"
            if chrome_src.exists():
                shutil.copy2(chrome_src, bm_dir / "chrome_bookmarks.json")
            # Edge
            edge_src = Path(user_dir) / "AppData" / "Local" / "Microsoft" / "Edge" / "User Data" / "Default" / "Bookmarks"
            if edge_src.exists():
                shutil.copy2(edge_src, bm_dir / "edge_bookmarks.json")
        elif key == "wifi":
            wifi_src = Path(mount_point) / "ProgramData" / "Microsoft" / "Wlansvc" / "Profiles" / "Interfaces"
            if wifi_src.exists():
                wifi_dst = import_dest / "wifi"
                wifi_dst.mkdir(exist_ok=True)
                for xml in wifi_src.rglob("*.xml"):
                    shutil.copy2(xml, wifi_dst)


# ============================================================
# Custom widgets
# ============================================================

class ToggleSwitch(QWidget):
    """Animated toggle switch."""
    def __init__(self, parent=None, checked=False):
        super().__init__(parent)
        self._checked = checked
        self.setFixedSize(48, 26)
        self.setCursor(Qt.CursorShape.PointingHandCursor)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        track_rect = self.rect().adjusted(1, 1, -1, -1)
        color = QColor("#34d399" if self._checked else "#334155")
        painter.setBrush(QBrush(color))
        painter.setPen(Qt.PenStyle.NoPen)
        painter.drawRoundedRect(track_rect, 13, 13)

        thumb_x = 22 if self._checked else 4
        thumb_rect = QRect(thumb_x, 3, 20, 20)
        painter.setBrush(QBrush(QColor("#ffffff")))
        painter.drawEllipse(thumb_rect)
        painter.end()

    def mousePressEvent(self, event):
        self._checked = not self._checked
        self.update()
        super().mousePressEvent(event)

    def isChecked(self):
        return self._checked

    def setChecked(self, checked):
        self._checked = checked
        self.update()


class ThemeCard(QFrame):
    selected = pyqtSignal(str)

    def __init__(self, theme_data, parent=None):
        super().__init__(parent)
        self.theme_id = theme_data["id"]
        self._selected = False
        self.setFixedSize(260, 320)
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setObjectName("themeCard")

        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)

        # Preview area
        preview = QFrame()
        preview.setFixedHeight(160)
        preview.setStyleSheet(f"""
            QFrame {{
                background: {theme_data['gradient']};
                border-radius: 12px;
            }}
        """)
        layout.addWidget(preview)

        # Title
        title = QLabel(theme_data["name"])
        title.setStyleSheet("color: #f1f5f9; font-size: 16px; font-weight: 600;")
        layout.addWidget(title)

        # Description
        desc = QLabel(theme_data["desc"])
        desc.setStyleSheet("color: #94a3b8; font-size: 13px;")
        desc.setWordWrap(True)
        layout.addWidget(desc)

        layout.addStretch()
        self.setStyleSheet("""
            #themeCard {
                background-color: #1e293b;
                border: 2px solid transparent;
                border-radius: 16px;
            }
            #themeCard:hover {
                background-color: #26344a;
            }
        """)

    def mousePressEvent(self, event):
        self.selected.emit(self.theme_id)

    def setActive(self, active):
        self._selected = active
        color = "#34d399" if active else "transparent"
        self.setStyleSheet(f"""
            #themeCard {{
                background-color: {'#26344a' if active else '#1e293b'};
                border: 2px solid {color};
                border-radius: 16px;
            }}
            #themeCard:hover {{
                background-color: #26344a;
            }}
        """)


class AppRow(QFrame):
    toggled = pyqtSignal(str, bool)

    def __init__(self, app_data, parent=None):
        super().__init__(parent)
        self.app_name = app_data["name"]
        self.setFixedHeight(72)
        self.setStyleSheet("""
            QFrame {
                background-color: #1e293b;
                border-radius: 12px;
            }
        """)

        layout = QHBoxLayout(self)
        layout.setContentsMargins(16, 8, 16, 8)
        layout.setSpacing(12)

        # Icon
        icon = QLabel(app_data["icon"])
        icon.setFixedSize(40, 40)
        icon.setAlignment(Qt.AlignmentFlag.AlignCenter)
        icon.setStyleSheet(f"""
            background-color: {app_data['color']};
            color: white;
            font-weight: bold;
            font-size: 16px;
            border-radius: 20px;
        """)
        layout.addWidget(icon)

        # Text
        text_layout = QVBoxLayout()
        text_layout.setSpacing(2)
        name = QLabel(app_data["name"])
        name.setStyleSheet("color: #f1f5f9; font-size: 14px; font-weight: 600;")
        text_layout.addWidget(name)
        desc = QLabel(app_data["desc"])
        desc.setStyleSheet("color: #94a3b8; font-size: 12px;")
        text_layout.addWidget(desc)
        layout.addLayout(text_layout, stretch=1)

        # Toggle
        self.toggle = ToggleSwitch()
        self.toggle.mousePressEvent = self._on_toggle
        layout.addWidget(self.toggle)

    def _on_toggle(self, event):
        self.toggle.setChecked(not self.toggle.isChecked())
        self.toggled.emit(self.app_name, self.toggle.isChecked())

    def isChecked(self):
        return self.toggle.isChecked()


class ImportRow(QFrame):
    toggled = pyqtSignal(str, bool)

    def __init__(self, item_data, parent=None):
        super().__init__(parent)
        self.item_key = item_data["key"]
        self.setFixedHeight(56)
        self.setStyleSheet("""
            QFrame {
                background-color: #1e293b;
                border-radius: 10px;
            }
        """)

        layout = QHBoxLayout(self)
        layout.setContentsMargins(16, 8, 16, 8)

        label = QLabel(item_data["label"])
        label.setStyleSheet("color: #f1f5f9; font-size: 14px;")
        layout.addWidget(label, stretch=1)

        self.toggle = ToggleSwitch(checked=item_data.get("checked", True))
        self.toggle.mousePressEvent = self._on_toggle
        layout.addWidget(self.toggle)

    def _on_toggle(self, event):
        self.toggle.setChecked(not self.toggle.isChecked())
        self.toggled.emit(self.item_key, self.toggle.isChecked())

    def isChecked(self):
        return self.toggle.isChecked()


# ============================================================
# Wizard pages
# ============================================================

class ThemePage(QWidget):
    theme_chosen = pyqtSignal(str)

    def __init__(self):
        super().__init__()
        layout = QVBoxLayout(self)
        layout.setContentsMargins(48, 40, 48, 40)
        layout.setSpacing(24)

        title = QLabel("Pick your style")
        title.setStyleSheet("color: #f8fafc; font-size: 28px; font-weight: 700;")
        layout.addWidget(title)

        subtitle = QLabel("You can always change this later in System Settings.")
        subtitle.setStyleSheet("color: #94a3b8; font-size: 14px;")
        layout.addWidget(subtitle)

        cards_layout = QHBoxLayout()
        cards_layout.setSpacing(20)
        cards_layout.addStretch()

        self.cards = []
        for theme in THEMES:
            card = ThemeCard(theme)
            card.selected.connect(self._on_select)
            cards_layout.addWidget(card)
            self.cards.append(card)
        cards_layout.addStretch()
        layout.addLayout(cards_layout, stretch=1)

        self._on_select("win11")

    def _on_select(self, theme_id):
        for card in self.cards:
            card.setActive(card.theme_id == theme_id)
        self.theme_chosen.emit(theme_id)


class AppsPage(QWidget):
    def __init__(self):
        super().__init__()
        layout = QVBoxLayout(self)
        layout.setContentsMargins(48, 40, 48, 40)
        layout.setSpacing(20)

        title = QLabel("Install your apps")
        title.setStyleSheet("color: #f8fafc; font-size: 28px; font-weight: 700;")
        layout.addWidget(title)

        subtitle = QLabel("Toggle the ones you want. We'll handle the rest.")
        subtitle.setStyleSheet("color: #94a3b8; font-size: 14px;")
        layout.addWidget(subtitle)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet("QScrollArea { border: none; background: transparent; }")
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)

        container = QWidget()
        container_layout = QVBoxLayout(container)
        container_layout.setSpacing(10)
        container_layout.setContentsMargins(0, 0, 12, 0)

        self.app_rows = {}
        for app in APPS:
            row = AppRow(app)
            container_layout.addWidget(row)
            self.app_rows[app["name"]] = row

        container_layout.addStretch()
        scroll.setWidget(container)
        layout.addWidget(scroll, stretch=1)

    def get_selected_apps(self):
        return [name for name, row in self.app_rows.items() if row.isChecked()]


class ImportPage(QWidget):
    import_requested = pyqtSignal(list)

    def __init__(self):
        super().__init__()
        layout = QVBoxLayout(self)
        layout.setContentsMargins(48, 40, 48, 40)
        layout.setSpacing(20)

        title = QLabel("Bring your files")
        title.setStyleSheet("color: #f8fafc; font-size: 28px; font-weight: 700;")
        layout.addWidget(title)

        self.subtitle = QLabel("Detecting Windows partition…")
        self.subtitle.setStyleSheet("color: #94a3b8; font-size: 14px;")
        layout.addWidget(self.subtitle)

        self.progress = QProgressBar()
        self.progress.setTextVisible(True)
        self.progress.setStyleSheet("""
            QProgressBar {
                background-color: #1e293b;
                border-radius: 6px;
                height: 20px;
                color: #f8fafc;
                font-size: 11px;
            }
            QProgressBar::chunk {
                background-color: #34d399;
                border-radius: 6px;
            }
        """)
        self.progress.setVisible(False)
        layout.addWidget(self.progress)

        self.rows_widget = QWidget()
        rows_layout = QVBoxLayout(self.rows_widget)
        rows_layout.setSpacing(8)
        rows_layout.setContentsMargins(0, 0, 0, 0)

        self.import_rows = {}
        for item in IMPORT_ITEMS:
            row = ImportRow(item)
            rows_layout.addWidget(row)
            self.import_rows[item["key"]] = row

        rows_layout.addStretch()
        layout.addWidget(self.rows_widget, stretch=1)

        self.windows_part = None
        self.win_user_dir = None
        self._detect_windows()

    def _detect_windows(self):
        try:
            result = subprocess.run(
                ["lsblk", "-rno", "NAME,FSTYPE,MOUNTPOINT"],
                capture_output=True, text=True
            )
            for line in result.stdout.splitlines():
                parts = line.split()
                if len(parts) >= 2 and parts[1] == "ntfs":
                    if len(parts) == 2 or parts[2] == "":
                        self.windows_part = f"/dev/{parts[0]}"
                        break
        except Exception:
            pass

        if self.windows_part:
            self.subtitle.setText(f"Found Windows at {self.windows_part}. Select what to import.")
            self.rows_widget.setEnabled(True)
            self._find_user_dir()
        else:
            self.subtitle.setText("No Windows partition detected. You can skip this step.")
            self.rows_widget.setEnabled(False)

    def _find_user_dir(self):
        mp = "/tmp/win_detect_gui"
        try:
            subprocess.run(["mkdir", "-p", mp], check=True)
            subprocess.run(["sudo", "mount", "-o", "ro", self.windows_part, mp], check=True)
            users_dir = None
            for p in Path(mp).glob("*/Users"):
                if p.is_dir():
                    users_dir = p
                    break
            if users_dir is None:
                users_dir = Path(mp) / "Users"
            if users_dir.exists():
                for d in users_dir.iterdir():
                    if d.is_dir() and d.name not in ("Public", "Default", "All Users"):
                        self.win_user_dir = str(d)
                        break
                if not self.win_user_dir:
                    self.win_user_dir = str(users_dir / "Public")
            subprocess.run(["sudo", "umount", mp], check=False)
        except Exception as e:
            print(f"User dir detection error: {e}")

    def get_selected_items(self):
        if not self.windows_part:
            return []
        return [
            {"key": k, "label": r.findChild(QLabel).text()}
            for k, r in self.import_rows.items() if r.isChecked()
        ]


class FinalPage(QWidget):
    restart_clicked = pyqtSignal()
    later_clicked = pyqtSignal()

    def __init__(self):
        super().__init__()
        layout = QVBoxLayout(self)
        layout.setContentsMargins(48, 60, 48, 48)
        layout.setSpacing(20)
        layout.setAlignment(Qt.AlignmentFlag.AlignCenter)

        # Animated checkmark (simple QLabel with emoji for now; could be SVG)
        self.check = QLabel("✓")
        self.check.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.check.setStyleSheet("""
            color: #34d399;
            font-size: 72px;
            font-weight: bold;
        """)
        layout.addWidget(self.check)

        title = QLabel("You're all set!")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        title.setStyleSheet("color: #f8fafc; font-size: 32px; font-weight: 700;")
        layout.addWidget(title)

        self.summary = QLabel("AltOS is ready.")
        self.summary.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.summary.setWordWrap(True)
        self.summary.setStyleSheet("color: #94a3b8; font-size: 15px;")
        layout.addWidget(self.summary)

        layout.addSpacing(24)

        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(16)

        self.restart_btn = QPushButton("Restart now")
        self.restart_btn.setFixedSize(180, 48)
        self.restart_btn.setStyleSheet("""
            QPushButton {
                background-color: #34d399;
                color: #0f172a;
                font-size: 14px;
                font-weight: 600;
                border-radius: 24px;
                border: none;
            }
            QPushButton:hover {
                background-color: #10b981;
            }
        """)
        self.restart_btn.clicked.connect(self.restart_clicked.emit)
        btn_layout.addWidget(self.restart_btn)

        self.later_btn = QPushButton("I'll restart later")
        self.later_btn.setFixedSize(180, 48)
        self.later_btn.setStyleSheet("""
            QPushButton {
                background-color: transparent;
                color: #94a3b8;
                font-size: 14px;
                font-weight: 500;
                border-radius: 24px;
                border: 1px solid #334155;
            }
            QPushButton:hover {
                background-color: #1e293b;
                color: #f1f5f9;
            }
        """)
        self.later_btn.clicked.connect(self.later_clicked.emit)
        btn_layout.addWidget(self.later_btn)

        layout.addLayout(btn_layout)
        layout.addStretch()


# ============================================================
# Main window
# ============================================================

class WizardWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.selected_theme = "win11"
        self.app_workers = []
        self.import_worker = None

        self.setWindowFlags(Qt.WindowType.FramelessWindowHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setMinimumSize(960, 720)
        self.resize(960, 720)

        # Center on screen
        screen = QApplication.primaryScreen().geometry()
        self.move(
            (screen.width() - self.width()) // 2,
            (screen.height() - self.height()) // 2,
        )

        # Central rounded container
        container = QWidget()
        container.setObjectName("wizardContainer")
        container.setStyleSheet("""
            #wizardContainer {
                background-color: #0f172a;
                border-radius: 20px;
                border: 1px solid #1e293b;
            }
        """)
        self.setCentralWidget(container)

        shadow = QGraphicsDropShadowEffect()
        shadow.setBlurRadius(40)
        shadow.setColor(QColor(0, 0, 0, 120))
        shadow.setOffset(0, 8)
        container.setGraphicsEffect(shadow)

        layout = QVBoxLayout(container)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        # Title bar
        title_bar = QWidget()
        title_bar.setFixedHeight(52)
        title_bar.setStyleSheet("background-color: transparent;")
        tb_layout = QHBoxLayout(title_bar)
        tb_layout.setContentsMargins(20, 8, 20, 8)

        logo = QLabel("AltOS")
        logo.setStyleSheet("color: #34d399; font-size: 16px; font-weight: 700;")
        tb_layout.addWidget(logo)

        tb_layout.addStretch()

        self.skip_btn = QPushButton("Skip")
        self.skip_btn.setStyleSheet("""
            QPushButton {
                background: transparent;
                color: #64748b;
                font-size: 13px;
                border: none;
                padding: 4px 12px;
            }
            QPushButton:hover {
                color: #f1f5f9;
            }
        """)
        self.skip_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.skip_btn.clicked.connect(self._on_skip)
        tb_layout.addWidget(self.skip_btn)

        layout.addWidget(title_bar)

        # Stacked pages
        self.stack = QStackedWidget()
        layout.addWidget(self.stack, stretch=1)

        self.theme_page = ThemePage()
        self.theme_page.theme_chosen.connect(self._on_theme_chosen)
        self.stack.addWidget(self.theme_page)

        self.apps_page = AppsPage()
        self.stack.addWidget(self.apps_page)

        self.import_page = ImportPage()
        self.stack.addWidget(self.import_page)

        self.final_page = FinalPage()
        self.final_page.restart_clicked.connect(self._on_restart)
        self.final_page.later_clicked.connect(self._on_done)
        self.stack.addWidget(self.final_page)

        # Bottom nav
        nav = QWidget()
        nav.setFixedHeight(80)
        nav.setStyleSheet("background-color: transparent;")
        nav_layout = QHBoxLayout(nav)
        nav_layout.setContentsMargins(40, 12, 40, 20)
        nav_layout.setSpacing(16)

        self.back_btn = QPushButton("Back")
        self.back_btn.setFixedSize(100, 40)
        self.back_btn.setStyleSheet("""
            QPushButton {
                background: transparent;
                color: #94a3b8;
                font-size: 13px;
                font-weight: 500;
                border-radius: 20px;
                border: 1px solid #334155;
            }
            QPushButton:hover {
                background: #1e293b;
                color: #f1f5f9;
            }
        """)
        self.back_btn.clicked.connect(self._prev_page)
        nav_layout.addWidget(self.back_btn)

        nav_layout.addStretch()

        # Dots
        self.dots = []
        dots_widget = QWidget()
        dots_layout = QHBoxLayout(dots_widget)
        dots_layout.setSpacing(8)
        dots_layout.setContentsMargins(0, 0, 0, 0)
        for i in range(4):
            dot = QLabel("●")
            dot.setStyleSheet(f"color: {'#34d399' if i == 0 else '#334155'}; font-size: 10px;")
            dots_layout.addWidget(dot)
            self.dots.append(dot)
        nav_layout.addWidget(dots_widget)

        nav_layout.addStretch()

        self.next_btn = QPushButton("Next")
        self.next_btn.setFixedSize(120, 40)
        self.next_btn.setStyleSheet("""
            QPushButton {
                background-color: #34d399;
                color: #0f172a;
                font-size: 13px;
                font-weight: 600;
                border-radius: 20px;
                border: none;
            }
            QPushButton:hover {
                background-color: #10b981;
            }
        """)
        self.next_btn.clicked.connect(self._next_page)
        nav_layout.addWidget(self.next_btn)

        layout.addWidget(nav)

        self._update_nav()

    def _update_nav(self):
        idx = self.stack.currentIndex()
        self.back_btn.setVisible(idx > 0)
        self.skip_btn.setVisible(idx < 3)
        self.next_btn.setText("Get Started" if idx == 3 else "Next")

        for i, dot in enumerate(self.dots):
            dot.setStyleSheet(f"color: {'#34d399' if i == idx else '#334155'}; font-size: 10px;")

    def _animate_page_change(self, new_idx):
        current = self.stack.currentWidget()
        self.stack.setCurrentIndex(new_idx)
        target = self.stack.currentWidget()

        anim = QPropertyAnimation(target, b"pos")
        anim.setDuration(350)
        anim.setEasingCurve(QEasingCurve.Type.OutCubic)
        direction = 1 if new_idx > self.stack.currentIndex() else -1
        # Actually, use the previous index for direction
        start_x = 60 * (1 if new_idx > getattr(self, '_prev_idx', 0) else -1)
        target.move(target.x() + start_x, target.y())
        anim.setStartValue(QPoint(target.x() + start_x, target.y()))
        anim.setEndValue(QPoint(0, target.y()))
        anim.start()

    def _prev_idx(self):
        return self.stack.currentIndex()

    def _next_page(self):
        idx = self.stack.currentIndex()
        if idx == 0:
            # Theme selected, apply it in background
            self._apply_theme(self.selected_theme)
        elif idx == 1:
            # Install selected apps
            self._install_apps()
        elif idx == 2:
            # Run import
            self._run_import()
        elif idx == 3:
            self._on_restart()
            return

        if idx < 3:
            old_idx = idx
            self.stack.setCurrentIndex(idx + 1)
            self._slide_in(old_idx, idx + 1)
            self._update_nav()

    def _prev_page(self):
        idx = self.stack.currentIndex()
        if idx > 0:
            old_idx = idx
            self.stack.setCurrentIndex(idx - 1)
            self._slide_in(old_idx, idx - 1)
            self._update_nav()

    def _slide_in(self, from_idx, to_idx):
        w = self.stack.currentWidget()
        delta = 50 if to_idx > from_idx else -50
        anim = QPropertyAnimation(w, b"pos")
        anim.setDuration(300)
        anim.setEasingCurve(QEasingCurve.Type.OutCubic)
        anim.setStartValue(QPoint(delta, 0))
        anim.setEndValue(QPoint(0, 0))
        anim.start()

    def _on_theme_chosen(self, theme_id):
        self.selected_theme = theme_id

    def _apply_theme(self, theme_id):
        self.worker = ThemeApplyWorker(theme_id)
        self.worker.start()

    def _install_apps(self):
        selected = self.apps_page.get_selected_apps()
        if not selected:
            return
        # For simplicity, install sequentially
        self._install_next_app(selected)

    def _install_next_app(self, names):
        if not names:
            return
        name = names[0]
        app_info = next((a for a in APPS if a["name"] == name), None)
        if not app_info:
            self._install_next_app(names[1:])
            return

        worker = AppInstallWorker(app_info)
        worker.finished.connect(lambda n, s, m: self._install_next_app(names[1:]))
        worker.start()
        self.app_workers.append(worker)

    def _run_import(self):
        items = self.import_page.get_selected_items()
        if not items:
            return
        self.import_page.progress.setVisible(True)
        self.import_worker = ImportWorker(
            items, self.import_page.windows_part, self.import_page.win_user_dir
        )
        self.import_worker.progress.connect(self._on_import_progress)
        self.import_worker.finished.connect(self._on_import_finished)
        self.import_worker.start()

    def _on_import_progress(self, label, pct):
        self.import_page.progress.setValue(pct)
        self.import_page.progress.setFormat(f"Importing {label}… {pct}%")

    def _on_import_finished(self, success, message):
        self.import_page.progress.setVisible(False)
        # Build summary
        apps = self.apps_page.get_selected_apps()
        theme = next((t for t in THEMES if t["id"] == self.selected_theme), None)
        parts = []
        if theme:
            parts.append(f"{theme['name']} theme")
        if apps:
            parts.append(", ".join(apps))
        summary = f"AltOS is ready with {', '.join(parts)}." if parts else "AltOS is ready."
        self.final_page.summary.setText(summary)

    def _on_skip(self):
        self._on_done()

    def _on_restart(self):
        self._mark_done()
        try:
            subprocess.Popen(["sudo", "reboot"])
        except Exception:
            pass
        QApplication.quit()

    def _on_done(self):
        self._mark_done()
        QApplication.quit()

    @staticmethod
    def _mark_done():
        DONE_FLAG.parent.mkdir(parents=True, exist_ok=True)
        DONE_FLAG.write_text("1")


# ============================================================
# Entry point
# ============================================================

def main():
    # Check if already run
    if DONE_FLAG.exists():
        print("First-boot wizard already completed.")
        sys.exit(0)

    app = QApplication(sys.argv)

    # Load stylesheet if present next to the script
    qss_path = Path(__file__).parent / "wizard.qss"
    if qss_path.exists():
        app.setStyleSheet(qss_path.read_text())

    # Global font
    font = QFont("Inter", 10)
    if not QFontDatabase.hasFamily("Inter"):
        font = QFont("Noto Sans", 10)
    app.setFont(font)

    window = WizardWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
