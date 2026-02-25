# Speech-to-Text for Claude Code — Conversation Notes

## Goal
Simple speech-to-text that works seamlessly with Claude Code on macOS.

## Requirements
- Speech to text only — no conversational AI features
- Toggle recording with **Option+W** (press to start, press to stop)
- Transcribe and paste text at cursor, then user presses Enter to submit
- Must work with Bluetooth headsets (Sony WH-1000XM4)
- No silence detection — manual toggle only
- Prefer **Parakeet v2** model (nvidia/parakeet-tdt-0.6b-v2 from HuggingFace)
- Run locally, no paid services

## Rejected Options
- **macOS built-in Dictation** — works but user wants better/custom solution
- **Superwhisper** — don't want to pay monthly for something that runs locally
- **super-voice-assistant** — stops working with XM4 Bluetooth headset

## Technical Plan

### Components
1. **Recording**: `sox` — record from system default mic input
2. **Transcription**: Parakeet v2 (nvidia NeMo 0.6B model) via Python
3. **Hotkey**: Hammerspoon — bind Option+W to toggle recording on/off
4. **Text injection**: `pbpaste` / `osascript` to type result at cursor

### Parakeet v2 on macOS Notes
- NVIDIA NeMo model — no Metal/GPU acceleration on macOS
- 0.6B model is small enough for CPU inference
- Needs Python + `nemo_toolkit`
- No CUDA on macOS, will fall back to CPU (or potentially MPS)

### Architecture
- Option+W → start recording with sox
- Option+W again → stop recording
- Run Parakeet v2 transcription on the audio file
- Paste transcribed text at cursor position

### Estimated Effort
- Working prototype: ~1 hour
- Polished version: ~afternoon

### Open Questions
- Can NeMo/Parakeet v2 run on macOS without CUDA? (should work on CPU)
- MPS backend support for NeMo?
- Need to handle Bluetooth audio device switching in sox config
