"""Original prototype SFX; Python stdlib only, deterministic, no external samples.

Run from any directory. Writes mono 44.1 kHz PCM16 WAV into assets/audio/sfx.
Not an audio-model output or a recording; review the sound in Godot before release.
"""
import array
import hashlib
import json
import math
from pathlib import Path
import random
import sys
import wave

RATE = 44100
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "sfx"


def make(kind, duration, seed):
    rng = random.Random(seed)
    samples = []
    low = high = 0.0
    count = round(RATE * duration)
    for index in range(count):
        t = index / RATE
        p = index / (count - 1)
        noise = rng.uniform(-1.0, 1.0)
        # Difference of two low-pass filters: softened, band-limited noise.
        cutoff = 4300 - 2100 * p if kind == "swing" else 3400 - 1300 * p
        a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
        b = 1 - math.exp(-2 * math.pi * 500 / RATE)
        high += a * (noise - high)
        low += b * (noise - low)
        band = high - low
        if kind == "swing":
            envelope = math.sin(math.pi * p) ** 1.7
            value = band * envelope
        else:
            attack = min(1.0, t / 0.003)
            tail = min(1.0, (duration - t) / 0.018)
            envelope = attack * math.exp(-30 * t) * tail
            body = 0.14 * math.sin(2 * math.pi * 185 * t) * math.exp(-40 * t)
            edge = 0.06 * math.sin(2 * math.pi * 920 * t) * math.exp(-65 * t)
            value = (band + body + edge) * envelope
        samples.append(value)
    mean = sum(samples) / count
    # Remove DC and taper both ends, including exactly zero first/last samples.
    samples = [(v - mean) * min(1, i / 80, (count - 1 - i) / 160)
               for i, v in enumerate(samples)]
    scale = (0.65 if kind == "swing" else 0.70) / max(abs(v) for v in samples)
    pcm = array.array("h", (round(v * scale * 32767) for v in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    path = OUT / f"sword_{kind}.wav"
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(pcm.tobytes())
    values = [v * scale for v in samples]
    assert all(abs(v) < 1 for v in values) and values[0] == values[-1] == 0
    return {"path": path.name, "seconds": duration, "sample_rate": RATE,
            "channels": 1, "peak": round(max(abs(v) for v in values), 4),
            "rms": round(math.sqrt(sum(v * v for v in values) / count), 5),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    print(json.dumps([make("swing", 0.16, 2901), make("hit", 0.12, 2902)], indent=2))
