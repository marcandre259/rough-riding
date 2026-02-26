#!/usr/bin/env python3
"""
Dictate — macOS menu bar speech-to-text app.

Click the mic icon or press Cmd+Option+Z to toggle recording.
Uses mlx-whisper for transcription via transcribe.py subprocess.
"""

import datetime
import logging
import os
import shutil
import signal
import subprocess
import threading

import rumps
from PyObjCTools.AppHelper import callAfter

# ── Paths ──
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
VENV_PYTHON = os.path.join(SCRIPT_DIR, ".venv", "bin", "python")
TRANSCRIBE_SCRIPT = os.path.join(SCRIPT_DIR, "transcribe.py")
RECORDING_PATH = "/tmp/dictate_recording.wav"
HISTORY_LOG = os.path.expanduser("~/.dictate_history.log")
LOG_FILE = os.path.expanduser("~/.dictate_app.log")

# ── Logging ──
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(message)s",
)
log = logging.getLogger("dictate")

# ── Icons ──
ICON_IDLE = "\U0001f399"       # 🎙
ICON_RECORDING = "\U0001f534"  # 🔴
ICON_TRANSCRIBING = "\u231b"   # ⏳

# ── Find sox's rec binary ──
REC_PATH = shutil.which("rec") or "/opt/homebrew/bin/rec"


class DictateApp(rumps.App):
    def __init__(self):
        super().__init__("Dictate", quit_button=None)
        self.title = ICON_IDLE
        self.recording_proc = None
        self.is_recording = False
        self.is_transcribing = False
        self._register_hotkey()
        log.info("DictateApp initialized")

    # ── Helper: look up toggle item fresh every time ──
    def _set_toggle_title(self, title):
        self.menu["Start Recording"].title = title

    # ── Menu callbacks via @rumps.clicked ──

    @rumps.clicked("Start Recording")
    def on_toggle(self, sender):
        log.info("on_toggle called, is_recording=%s", self.is_recording)
        if self.is_transcribing:
            return
        if self.is_recording:
            self._stop_recording()
        else:
            self._start_recording()

    @rumps.clicked("Quit")
    def on_quit(self, sender):
        if self.recording_proc:
            self.recording_proc.send_signal(signal.SIGTERM)
            self.recording_proc.wait()
            log.info("Killed recording on quit")
        log.info("Quitting")
        rumps.quit_application()

    # ── Global hotkey via NSEvent ──
    def _register_hotkey(self):
        # Try modern constant names first, fall back to legacy
        try:
            from AppKit import NSEvent, NSEventMaskKeyDown, NSEventModifierFlagCommand, NSEventModifierFlagOption
            mask = NSEventMaskKeyDown
            cmd_flag = NSEventModifierFlagCommand
            alt_flag = NSEventModifierFlagOption
        except ImportError:
            try:
                from AppKit import NSEvent, NSKeyDownMask, NSCommandKeyMask, NSAlternateKeyMask
                mask = NSKeyDownMask
                cmd_flag = NSCommandKeyMask
                alt_flag = NSAlternateKeyMask
            except ImportError:
                log.warning("Could not import NSEvent constants — hotkey disabled")
                return

        required_flags = cmd_flag | alt_flag

        def handler(event):
            if event.keyCode() == 6:  # Z
                flags = event.modifierFlags()
                if flags & required_flags == required_flags:
                    self.on_toggle(None)

        try:
            NSEvent.addGlobalMonitorForEventsMatchingMask_handler_(mask, handler)
            log.info("Global hotkey Cmd+Option+Z registered")
        except Exception as e:
            log.warning("Could not register global hotkey (grant Accessibility): %s", e)

    # ── Start recording ──
    def _start_recording(self):
        if os.path.exists(RECORDING_PATH):
            os.unlink(RECORDING_PATH)

        try:
            self.recording_proc = subprocess.Popen(
                [REC_PATH, "-r", "16000", "-c", "1", "-b", "16", RECORDING_PATH],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception as e:
            log.error("Failed to start recording: %s", e)
            rumps.notification("Dictate", "", f"Recording failed: {e}")
            return

        self.is_recording = True
        self.title = ICON_RECORDING
        self._set_toggle_title("Stop Recording")
        log.info("Recording started (PID %d)", self.recording_proc.pid)

    # ── Stop recording ──
    def _stop_recording(self):
        if not self.recording_proc:
            return

        self.is_recording = False
        self.title = ICON_TRANSCRIBING
        self._set_toggle_title("Transcribing...")

        # SIGTERM lets sox write proper WAV headers
        self.recording_proc.send_signal(signal.SIGTERM)
        self.recording_proc.wait()
        self.recording_proc = None
        log.info("Recording stopped")

        # Transcribe in background thread so UI stays responsive
        self.is_transcribing = True
        threading.Thread(target=self._transcribe, daemon=True).start()

    # ── Transcribe + paste (runs in thread) ──
    def _transcribe(self):
        try:
            if not os.path.exists(RECORDING_PATH):
                log.error("Recording file not found")
                return

            log.info("Transcribing %s", RECORDING_PATH)
            result = subprocess.run(
                [VENV_PYTHON, TRANSCRIBE_SCRIPT, RECORDING_PATH],
                capture_output=True,
                text=True,
                timeout=120,
            )

            if result.returncode != 0:
                log.error("Transcription failed: %s", result.stderr.strip())
                return

            text = result.stdout.strip()
            if not text:
                log.info("No speech detected")
                return

            log.info("Transcribed: %s", text)

            # Copy to clipboard
            subprocess.run(["/usr/bin/pbcopy"], input=text.encode(), check=True)

            # Append to history
            ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            with open(HISTORY_LOG, "a") as f:
                f.write(f"[{ts}] {text}\n")

            # Paste at cursor (Cmd+V)
            subprocess.run(
                ["osascript", "-e", 'tell application "System Events" to keystroke "v" using command down'],
                check=False,
            )

        except subprocess.TimeoutExpired:
            log.error("Transcription timed out")
        except Exception as e:
            log.error("Transcription error: %s", e)
        finally:
            if os.path.exists(RECORDING_PATH):
                os.unlink(RECORDING_PATH)
            # Schedule UI reset on the main thread — rumps.Timer from a background
            # thread won't fire because NSTimer needs an active run loop.
            callAfter(self._reset_ui)

    # ── Reset UI back to idle (called on main thread via callAfter) ──
    def _reset_ui(self):
        self.title = ICON_IDLE
        self._set_toggle_title("Start Recording")
        self.is_transcribing = False
        log.info("UI reset to idle")


if __name__ == "__main__":
    log.info("Dictate app starting")
    DictateApp().run()
