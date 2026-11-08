#!/usr/bin/env python3
"""Generate Mishkat's original non-verbal recitation cues, without downloads.

Run normally to regenerate the bundled PCM16 WAVs and their manifest. Use
--check to verify the committed files, durations, fades, clipping, and hashes.
No sampled voice, Quran recitation, or third-party sound is used.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
SAMPLE_RATE = 16000
ASSET_DIR = ROOT / "assets" / "audio"
MANIFEST = ROOT / "tools" / "recitation_feedback_manifest.json"


def pulse(
    samples: list[float],
    start_ms: float,
    duration_ms: float,
    start_hz: float,
    end_hz: float,
    gain: float,
    harmonic: float = 0.14,
) -> None:
    """A rounded, lightly harmonic pulse, with raised-cosine attack/release."""
    start = round(start_ms * SAMPLE_RATE / 1000)
    length = round(duration_ms * SAMPLE_RATE / 1000)
    duration = length / SAMPLE_RATE
    attack = min(0.014, duration * 0.25)
    release = min(0.028, duration * 0.4)
    for offset in range(length):
        t = offset / SAMPLE_RATE
        # Both endpoints are exactly zero, eliminating discontinuity clicks.
        rise = min(1.0, t / attack)
        fall = min(1.0, (length - 1 - offset) / SAMPLE_RATE / release)
        envelope = math.sin(math.pi * rise / 2) ** 2
        envelope *= math.sin(math.pi * fall / 2) ** 2
        phase = 2 * math.pi * (
            start_hz * t + 0.5 * (end_hz - start_hz) / duration * t * t
        )
        carrier = (math.sin(phase) + harmonic * math.sin(phase * 2)) / (1 + harmonic)
        samples[start + offset] += gain * envelope * carrier


def render() -> dict[str, tuple[list[int], str]]:
    definitions = {
        "ready": (105, "A single soft rising pulse: the microphone is ready."),
        "mistake": (180, "Two muted descending pulses: check a confirmed word."),
        "corrected": (105, "A light upward response: a flagged word was corrected."),
        "paused": (80, "A short low settling pulse: capture has stopped."),
        "complete": (210, "Two gentle upward pulses: the selected passage is complete."),
    }
    result = {}
    for name, (duration_ms, description) in definitions.items():
        samples = [0.0] * round(duration_ms * SAMPLE_RATE / 1000)
        if name == "ready":
            pulse(samples, 4, 97, 490, 590, 0.22)
        elif name == "mistake":
            pulse(samples, 3, 76, 390, 330, 0.29, harmonic=0.22)
            pulse(samples, 96, 81, 330, 285, 0.26, harmonic=0.22)
        elif name == "corrected":
            pulse(samples, 4, 97, 660, 760, 0.19)
        elif name == "paused":
            pulse(samples, 3, 74, 440, 360, 0.17)
        elif name == "complete":
            pulse(samples, 4, 83, 580, 650, 0.20)
            pulse(samples, 105, 101, 730, 820, 0.21)
        assert max(abs(value) for value in samples) < 0.31
        integers = [round(value * 32767) for value in samples]
        assert integers[0] == integers[-1] == 0
        result[name] = integers, description
    return result


def wav_bytes(samples: list[int]) -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(struct.pack(f"<{len(samples)}h", *samples))
    return buffer.getvalue()


def dbfs(value: float) -> float:
    return round(20 * math.log10(value), 2) if value > 0 else -120.0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify without modifying files")
    args = parser.parse_args()
    manifest = {
        "origin": "Original deterministic synthesis for Mishkat; no voice or third-party samples.",
        "sample_rate_hz": SAMPLE_RATE,
        "channels": 1,
        "sample_format": "PCM signed 16-bit little-endian",
        "playback_gain_android": 0.6,
        "validation_limit": "Signal checks do not prove subjective sound quality or microphone echo safety.",
        "cues": {},
    }
    for name, (samples, description) in render().items():
        data = wav_bytes(samples)
        path = ASSET_DIR / f"recitation_{name}.wav"
        peak = max(abs(value) for value in samples) / 32768
        rms = math.sqrt(sum(value * value for value in samples) / len(samples)) / 32768
        duration_ms = len(samples) * 1000 / SAMPLE_RATE
        assert 0 < duration_ms < 230
        assert 0 < peak < 0.31
        assert samples[:32] == samples[-32:] == [0] * 32
        if args.check:
            assert path.read_bytes() == data, f"Out-of-date WAV: {path}"
        else:
            path.write_bytes(data)
        manifest["cues"][name] = {
            "file": str(path.relative_to(ROOT)),
            "description": description,
            "duration_ms": duration_ms,
            "peak_dbfs": dbfs(peak),
            "rms_dbfs": dbfs(rms),
            "clipped_samples": sum(abs(value) >= 32767 for value in samples),
            "sha256": hashlib.sha256(data).hexdigest(),
        }
        print(f"{name:10} {duration_ms:5.0f} ms  peak {dbfs(peak):6.2f} dBFS  RMS {dbfs(rms):6.2f} dBFS")
    text = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    if args.check:
        assert MANIFEST.read_text() == text, f"Out-of-date manifest: {MANIFEST}"
    else:
        MANIFEST.write_text(text)


if __name__ == "__main__":
    main()
