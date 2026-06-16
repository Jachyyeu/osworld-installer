#!/usr/bin/env python3
"""
AltOS App Store — simple PyQt6 wrapper around pacman/flatpak.
Reads catalog.yaml and lets users install curated apps.
"""

import os
import sys
import subprocess
import yaml
from pathlib import Path

from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QListWidget, QListWidgetItem, QProgressBar,
    QTextEdit, QMessageBox, QSplitter, QFrame
)
from PyQt6.QtCore import Qt, QThread, pyqtSignal


CATALOG_PATH = Path(__file__).parent / "catalog.yaml"


def load_catalog():
    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


class InstallWorker(QThread):
    progress = pyqtSignal(str)
    finished = pyqtSignal(bool, str)

    def __init__(self, apps):
        super().__init__()
        self.apps = apps

    def run(self):
        total = len(self.apps)
        for idx, app in enumerate(self.apps, 1):
            name = app["name"]
            method = app.get("install_method", "pacman")
            package = app["package"]
            self.progress.emit(f"[{idx}/{total}] Installing {name}...")
            try:
                if method == "pacman":
                    subprocess.run(
                        ["pkexec", "pacman", "-S", "--noconfirm", package],
                        check=True,
                        capture_output=True,
                        text=True,
                    )
                elif method == "flatpak":
                    subprocess.run(
                        ["flatpak", "install", "-y", "flathub", package],
                        check=True,
                        capture_output=True,
                        text=True,
                    )
                else:
                    raise ValueError(f"Unknown install method: {method}")
                self.progress.emit(f"  ✓ {name} installed.")
            except subprocess.CalledProcessError as e:
                self.finished.emit(False, f"Failed to install {name}:\n{e.stderr or e.stdout}")
                return
            except Exception as e:
                self.finished.emit(False, f"Failed to install {name}:\n{str(e)}")
                return
        self.finished.emit(True, "All selected apps installed successfully.")


class AppStore(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("AltOS App Store")
        self.setMinimumSize(900, 600)
        self.catalog = load_catalog()
        self.apps_by_id = {app["id"]: app for app in self.catalog.get("apps", [])}
        self.selected_ids = set()
        self.worker = None

        central = QWidget()
        self.setCentralWidget(central)
        layout = QHBoxLayout(central)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(16)

        splitter = QSplitter(Qt.Orientation.Horizontal)

        # Left: categories + app list
        left = QWidget()
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 0, 0)

        left_layout.addWidget(QLabel("<h2>AltOS App Store</h2>"))
        left_layout.addWidget(QLabel("Pick apps to install on your AltOS system."))

        self.category_list = QListWidget()
        self.category_list.addItem("All")
        for cat in self.catalog.get("categories", []):
            item = QListWidgetItem(cat["name"])
            item.setData(Qt.ItemDataRole.UserRole, cat["id"])
            self.category_list.addItem(item)
        self.category_list.currentRowChanged.connect(self.filter_apps)
        left_layout.addWidget(self.category_list)

        self.app_list = QListWidget()
        self.app_list.setSelectionMode(QListWidget.SelectionMode.MultiSelection)
        self.populate_apps()
        self.app_list.itemSelectionChanged.connect(self.on_selection_changed)
        left_layout.addWidget(self.app_list, 2)

        splitter.addWidget(left)

        # Right: details + log + install button
        right = QWidget()
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(0, 0, 0, 0)

        self.details = QLabel("Select apps from the list to see details.")
        self.details.setWordWrap(True)
        self.details.setFrameShape(QFrame.Shape.StyledPanel)
        self.details.setStyleSheet("padding: 12px;")
        right_layout.addWidget(self.details)

        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        self.progress.setValue(0)
        self.progress.setTextVisible(True)
        right_layout.addWidget(self.progress)

        self.log = QTextEdit()
        self.log.setReadOnly(True)
        right_layout.addWidget(self.log, 2)

        self.install_btn = QPushButton("Install Selected")
        self.install_btn.setEnabled(False)
        self.install_btn.clicked.connect(self.start_install)
        right_layout.addWidget(self.install_btn)

        splitter.addWidget(right)
        splitter.setSizes([350, 550])
        layout.addWidget(splitter)

    def populate_apps(self):
        self.app_list.clear()
        for app in self.catalog.get("apps", []):
            item = QListWidgetItem(f"{app['name']}")
            item.setData(Qt.ItemDataRole.UserRole, app["id"])
            item.setToolTip(app.get("description", ""))
            self.app_list.addItem(item)

    def filter_apps(self):
        row = self.category_list.currentRow()
        if row <= 0:
            cat_id = None
        else:
            cat_id = self.category_list.item(row).data(Qt.ItemDataRole.UserRole)

        self.app_list.clear()
        for app in self.catalog.get("apps", []):
            if cat_id is None or app.get("category") == cat_id:
                item = QListWidgetItem(f"{app['name']}")
                item.setData(Qt.ItemDataRole.UserRole, app["id"])
                item.setToolTip(app.get("description", ""))
                self.app_list.addItem(item)

    def on_selection_changed(self):
        selected = self.app_list.selectedItems()
        self.selected_ids = {item.data(Qt.ItemDataRole.UserRole) for item in selected}
        self.install_btn.setEnabled(bool(self.selected_ids))

        if len(selected) == 1:
            app_id = selected[0].data(Qt.ItemDataRole.UserRole)
            app = self.apps_by_id.get(app_id, {})
            self.details.setText(
                f"<h3>{app.get('name', '')}</h3>"
                f"<p>{app.get('description', '')}</p>"
                f"<p><b>Category:</b> {app.get('category', '')}<br>"
                f"<b>Package:</b> {app.get('package', '')}<br>"
                f"<b>Method:</b> {app.get('install_method', '')}</p>"
            )
        elif len(selected) > 1:
            self.details.setText(f"{len(selected)} apps selected.")
        else:
            self.details.setText("Select apps from the list to see details.")

    def start_install(self):
        apps = [self.apps_by_id[a] for a in self.selected_ids]
        self.install_btn.setEnabled(False)
        self.log.clear()
        self.progress.setValue(0)

        self.worker = InstallWorker(apps)
        self.worker.progress.connect(self.on_progress)
        self.worker.finished.connect(self.on_finished)
        self.worker.start()

    def on_progress(self, message):
        self.log.append(message)
        # Rough progress based on log lines
        val = min(100, self.log.document().blockCount() * 5)
        self.progress.setValue(val)

    def on_finished(self, success, message):
        self.log.append(message)
        self.progress.setValue(100 if success else self.progress.value())
        self.install_btn.setEnabled(True)
        QMessageBox.information(self, "Installation Result", message)


def main():
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    window = AppStore()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
