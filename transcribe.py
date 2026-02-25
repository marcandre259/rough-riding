#!/usr/bin/env python3
"""Transcribe a WAV file to text using mlx-whisper (large-v3)."""

import sys

MODEL = "mlx-community/whisper-large-v3-mlx"


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <wav_file>", file=sys.stderr)
        sys.exit(1)

    wav_path = sys.argv[1]

    try:
        import mlx_whisper
    except ImportError:
        print("mlx_whisper not installed. Run: .venv/bin/pip install mlx-whisper", file=sys.stderr)
        sys.exit(1)

    # Check if audio has actual speech energy before transcribing
    import wave
    import struct
    import math

    with wave.open(wav_path, "r") as wf:
        frames = wf.readframes(wf.getnframes())
        samples = struct.unpack(f"<{len(frames) // 2}h", frames)
        rms = math.sqrt(sum(s * s for s in samples) / len(samples)) if samples else 0

    # RMS below ~200 for 16-bit audio is effectively silence
    if rms < 200:
        return

    result = mlx_whisper.transcribe(
        wav_path,
        path_or_hf_repo=MODEL,
        language="en",
        condition_on_previous_text=False,
    )
    text = result["text"].strip()
    if text:
        print(text)


if __name__ == "__main__":
    main()
