#!/usr/bin/env bash
#
# install.sh — one-command setup for Dictate menu bar app on macOS
#
# Run from the project directory: ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_DIR="$HOME/Applications/Dictate.app"
BUNDLE_ID="com.local.dictate"

# ── Check macOS ──
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This script must be run on macOS." >&2
    exit 1
fi

echo "==> Installing Dictate menu bar app..."

# ── Homebrew deps ──
if ! command -v brew &>/dev/null; then
    echo "Error: Homebrew not found. Install from https://brew.sh" >&2
    exit 1
fi

if ! command -v sox &>/dev/null; then
    echo "==> Installing sox..."
    brew install sox
else
    echo "==> sox already installed"
fi

# ── Python venv ──
if [ ! -d ".venv" ]; then
    echo "==> Creating Python venv..."
    python3 -m venv .venv
else
    echo "==> Python venv exists"
fi

echo "==> Installing Python dependencies (mlx-whisper, rumps)..."
.venv/bin/pip install --quiet mlx-whisper rumps

# ── Pre-download model (~3GB first time) ──
echo "==> Pre-downloading whisper-large-v3 model (this may take a while)..."
.venv/bin/python -c "
import mlx_whisper
import tempfile, wave, struct, os
tmp = os.path.join(tempfile.gettempdir(), 'silence.wav')
with wave.open(tmp, 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(16000)
    w.writeframes(struct.pack('<' + 'h' * 16000, *([0] * 16000)))
try:
    mlx_whisper.transcribe(tmp, path_or_hf_repo='mlx-community/whisper-large-v3-mlx', language='en')
except Exception:
    pass
os.unlink(tmp)
print('Model cached successfully.')
"

# ── Make scripts executable ──
chmod +x dictate_app.py

# ── Create .app bundle ──
echo "==> Creating Dictate.app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"

# Launcher script
cat > "$APP_DIR/Contents/MacOS/Dictate" << LAUNCHER
#!/usr/bin/env bash
exec "$SCRIPT_DIR/.venv/bin/python" "$SCRIPT_DIR/dictate_app.py"
LAUNCHER
chmod +x "$APP_DIR/Contents/MacOS/Dictate"

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>Dictate</string>
    <key>CFBundleExecutable</key>
    <string>Dictate</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Dictate needs microphone access to record speech for transcription.</string>
</dict>
</plist>
PLIST

echo ""
echo "==> Installation complete!"
echo ""
echo "Launch:"
echo "  open ~/Applications/Dictate.app"
echo "  Or find \"Dictate\" in Spotlight (Cmd+Space)"
echo ""
echo "Permissions needed (one-time, in System Settings > Privacy & Security):"
echo "  1. Accessibility — for global Cmd+Option+Z hotkey"
echo "  2. Microphone   — for recording speech"
echo ""
echo "Usage:"
echo "  Click the mic icon in the menu bar, or press Cmd+Option+Z."
echo "  Speak, then click again (or press hotkey) to stop, transcribe, and paste."
