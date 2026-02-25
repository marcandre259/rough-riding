#!/usr/bin/env bash
#
# dictate.sh — toggle speech recording, transcribe, copy & paste
#
# Usage: dictate.sh {start|stop|toggle}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECORDING="/tmp/dictate_recording.wav"
PID_FILE="/tmp/dictate.pid"
HISTORY_LOG="$HOME/.dictate_history.log"
PYTHON="$SCRIPT_DIR/.venv/bin/python"
TRANSCRIBE="$SCRIPT_DIR/transcribe.py"

# macOS paths
REC="/opt/homebrew/bin/rec"
PBCOPY="/usr/bin/pbcopy"

is_recording() {
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

do_start() {
    # Kill stale recording if any
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        kill "$old_pid" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    rm -f "$RECORDING"

    # Record: 16kHz mono 16-bit WAV from system default mic
    # Redirect output and disown so hs.task pipes close when bash exits
    "$REC" -r 16000 -c 1 -b 16 "$RECORDING" >/dev/null 2>&1 &
    echo $! > "$PID_FILE"
    echo "Recording started (PID $(cat "$PID_FILE"))" >&2
}

do_stop() {
    if [[ ! -f "$PID_FILE" ]]; then
        echo "Not recording" >&2
        exit 1
    fi

    local pid
    pid=$(cat "$PID_FILE")
    rm -f "$PID_FILE"

    # SIGTERM lets sox write proper WAV headers
    kill "$pid" 2>/dev/null || true
    sleep 0.3

    if [[ ! -f "$RECORDING" ]]; then
        echo "No recording file found" >&2
        exit 1
    fi

    # Transcribe
    echo "Transcribing..." >&2
    text=$("$PYTHON" "$TRANSCRIBE" "$RECORDING")

    if [[ -z "$text" ]]; then
        echo "No speech detected" >&2
        rm -f "$RECORDING"
        exit 0
    fi

    # Copy to clipboard
    printf '%s' "$text" | "$PBCOPY"

    # Append to history log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $text" >> "$HISTORY_LOG"

    # Paste at cursor via Cmd+V
    osascript -e 'tell application "System Events" to keystroke "v" using command down'

    echo "Transcribed: $text" >&2
    rm -f "$RECORDING"
}

do_toggle() {
    if is_recording; then
        do_stop
    else
        do_start
    fi
}

case "${1:-}" in
    start)  do_start ;;
    stop)   do_stop ;;
    toggle) do_toggle ;;
    *)
        echo "Usage: $0 {start|stop|toggle}" >&2
        exit 1
        ;;
esac
