#!/usr/bin/env python3
# menubar.py — macOS menu-bar status indicator + control panel for keep-awake.
# Shows the current mode in the top-right menu bar (refreshes every 3s) and lets
# you switch modes / stop from the dropdown. Requires: rumps  (pip install rumps)
#
# NOTE: do NOT use rumps.alert() (modal) here — a modal blocks the run loop and
# freezes the whole menu bar until dismissed. Surface hints in the detail row.

import os
import subprocess

import rumps

HERE = os.path.dirname(os.path.realpath(__file__))
SCRIPT = os.path.join(HERE, "keep-awake.sh")
STATE_DIR = os.path.expanduser("~/.keep-awake")
MODE_FILE = os.path.join(STATE_DIR, "mode")
PID_FILE = os.path.join(STATE_DIR, "caffeinate.pid")
STRONG_FILE = os.path.join(STATE_DIR, "strong")

NAMES = {"super": "Super", "flex": "Flex", "normal": "Normal", "": "Off"}


def read_mode():
    try:
        with open(MODE_FILE) as f:
            return f.read().strip()
    except OSError:
        return ""


def caffeinate_running():
    try:
        with open(PID_FILE) as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        return True
    except (OSError, ValueError):
        return False


def strong_on():
    return os.path.exists(STRONG_FILE)


def compute_title():
    mode = read_mode()
    if mode == "super":
        return "Awake: Super"
    if mode == "flex":
        return "Awake: Flex" if caffeinate_running() else "Flex (idle)"
    if mode == "normal":
        return "Awake: Normal"
    return "Sleep OK"


class KeepAwakeBar(rumps.App):
    def __init__(self):
        super().__init__("Sleep OK", quit_button=None)
        self.detail = rumps.MenuItem("Current: -")  # no callback => greyed info row
        self.item_super = rumps.MenuItem("Super — never sleep", callback=self.set_super)
        self.item_flex = rumps.MenuItem("Flex — sleep when idle", callback=self.set_flex)
        self.item_normal = rumps.MenuItem("Normal — display only", callback=self.set_normal)
        self.item_off = rumps.MenuItem("Stop (allow sleep)", callback=self.set_off)
        self.menu = [
            self.detail,
            None,
            self.item_super,
            self.item_flex,
            self.item_normal,
            self.item_off,
            None,
            rumps.MenuItem("Refresh", callback=lambda _: self.refresh(None)),
            rumps.MenuItem("Quit this icon", callback=lambda _: rumps.quit_application()),
        ]
        self.timer = rumps.Timer(self.refresh, 3)
        self.timer.start()
        self.refresh(None)

    def _run(self, *args):
        subprocess.run(["bash", SCRIPT, *args], capture_output=True, text=True)

    def set_super(self, _):
        self._run("on", "super"); self.refresh(None)

    def set_flex(self, _):
        self._run("on", "flex"); self.refresh(None)

    def set_normal(self, _):
        self._run("on", "normal"); self.refresh(None)

    def set_off(self, _):
        self._run("off"); self.refresh(None)

    def refresh(self, _):
        self.title = compute_title()
        mode = read_mode()
        if mode == "flex":
            base = "Flex (working)" if caffeinate_running() else "Flex (idle)"
        else:
            base = NAMES.get(mode, mode)
        if mode in ("super", "flex"):
            tag = " | lid-proof on 🛡️" if strong_on() else " | ⚠️ lid still sleeps (needs auth)"
        else:
            tag = ""
        self.detail.title = f"Current: {base}{tag}"
        self.item_super.state = 1 if mode == "super" else 0
        self.item_flex.state = 1 if mode == "flex" else 0
        self.item_normal.state = 1 if mode == "normal" else 0
        self.item_off.state = 1 if mode == "" else 0


if __name__ == "__main__":
    KeepAwakeBar().run()
