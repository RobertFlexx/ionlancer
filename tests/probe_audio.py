#!/usr/bin/env python3
"""Check captured soundtrack output for silence, clipping, and duplicate songs."""
import array
import hashlib
import math
from pathlib import Path

digests = set()
for track in range(9):
    data = Path(f"build/quality-probe/track-{track}.s16").read_bytes()
    samples = array.array("h", data)
    assert len(samples) >= 44100 * 10, f"track {track} is too short"
    rms = math.sqrt(sum(value * value for value in samples) / len(samples))
    assert 1000 < rms < 8000, f"track {track} has inconsistent output level: {rms}"
    assert max(map(abs, samples)) < 32767, f"track {track} clips"
    assert abs(sum(samples) / len(samples)) < 150, f"track {track} has excessive DC offset"
    digest = hashlib.sha256(data).digest()
    assert digest not in digests, f"track {track} duplicates another song"
    digests.add(digest)

print("All nine soundtracks: distinct output, audible levels, no clipping, low DC offset")
