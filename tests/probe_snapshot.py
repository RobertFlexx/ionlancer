#!/usr/bin/env python3
"""Make the real guest reject invalid fields, replays, and out-of-order snapshots."""
import socket
import subprocess
import sys
import time


def snapshot(sequence, lives=3, paused=True):
    data = bytearray(472)
    data[:10] = b"IL\x03\x02" + sequence.to_bytes(2, "little") + bytes((0, 2 if paused else 0, 0, 1))
    data[14:16] = (10800).to_bytes(2, "little")
    for offset, x in ((27, 70), (37, 250)):
        data[offset:offset+2] = (x+32).to_bytes(2, "little")
        data[offset+2] = 126
        data[offset+3] = lives
    return data


with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as host:
    host.bind(("127.0.0.1", 37177))
    host.settimeout(0.008)
    process = subprocess.Popen([sys.argv[1]])
    start = time.monotonic()
    mutations = [(7, 4), (8, 4), (9, 0), (9, 9), (16, 4), (18, 76),
                 (30, 5), (32, 101), (33, 5), (34, 7), (35, 2), (47, 2),
                 (28, 255), (29, 255), (49, 255), (51, 1), (54, 255), (55, 8),
                 (56, 2), (60, 2), (61, 4), (249, 11), (253, 33), (344, 2)]
    try:
        while process.poll() is None:
            try:
                _, address = host.recvfrom(600)
            except socket.timeout:
                continue
            elapsed = time.monotonic()-start
            if elapsed < 0.65:
                # All invalid frames are rejected before changing any state.
                for offset, value in mutations:
                    data = snapshot(65530)
                    data[offset] = value
                    host.sendto(data, address)
            elif elapsed < 1.15:
                host.sendto(snapshot(65530), address)
            else:
                # Accept sequence wrap, then reject a conflicting duplicate
                # and an older frame even though they have valid field ranges.
                host.sendto(snapshot(1, lives=2, paused=False), address)
                host.sendto(snapshot(1, lives=4, paused=True), address)
                host.sendto(snapshot(65520, lives=4, paused=True), address)
        status = process.wait()
        assert status == 0, f"guest snapshot validation probe failed: status={status}"
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait()

print("Guest field validation, pause flags, duplicate rejection, and sequence wrap passed")
