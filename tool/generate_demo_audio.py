"""Generate original, deterministic 120 BPM loops; no third-party samples."""
import math
import random
import struct
import wave
from pathlib import Path

out = Path(__file__).resolve().parent.parent / 'example/assets/audio'
out.mkdir(parents=True, exist_ok=True)
rate = 22050
for name, root in [('daylight', 130.8128), ('motion', 164.8138), ('afterglow', 146.8324)]:
    rng = random.Random(42)
    frames = bytearray()
    for i in range(rate * 16):
        t = i / rate
        beat = t % .5
        step = t % .25
        chord = [1, 1.259921, 1.498307]
        bass = .18 * math.sin(2 * math.pi * root / 2 * t) * math.exp(-beat * 7)
        kick = .27 * math.sin(2 * math.pi * (48 * beat + 7 * (1 - math.exp(-beat * 35)))) * math.exp(-beat * 24)
        hat = .035 * rng.uniform(-1, 1) * math.exp(-step * 85)
        lead_hz = root * 2 * chord[int(t * 4) % 3]
        lead = .08 * (math.sin(2 * math.pi * lead_hz * t) + .3 * math.sin(2 * math.pi * lead_hz * 3 * t)) * math.exp(-step * 12)
        pad = sum(.025 * math.sin(2 * math.pi * root * n * t) for n in chord)
        edge = min(1, t / .005, (16 - t) / .005)
        sample = int(max(-1, min(1, (bass + kick + hat + lead + pad) * edge)) * 32767)
        frames.extend(struct.pack('<hh', sample, sample))
    with wave.open(str(out / f'{name}.wav'), 'wb') as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(frames)
