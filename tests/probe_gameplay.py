#!/usr/bin/env python3
"""Compare deterministic combat frames with the pre-update 2.0.0 build."""
import hashlib
from pathlib import Path

count = 0
for line in Path("tests/gameplay.sha256").read_text().splitlines():
    expected, filename = line.split(maxsplit=1)
    actual = hashlib.sha256(Path(filename).read_bytes()).hexdigest()
    assert actual == expected, f"gameplay changed from the original build: {filename}"
    count += 1

assert count == 75, "gameplay fixture roster is incomplete"
print("75 original gameplay frames match across all solo modes, ships, and modifiers")
