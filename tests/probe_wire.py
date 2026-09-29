#!/usr/bin/env python3
"""Check that a firing guest gets v2 snapshots with gameplay sound events."""

import socket
import time


peer = ("127.0.0.1", 37177)
laser_seen = False
jingle_seen = False
snapshot_seen = False

with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
    client.settimeout(0.008)
    deadline = time.monotonic() + 2.5
    sequence = 0
    while time.monotonic() < deadline and not (laser_seen and jingle_seen):
        packet = b"IL\x02\x01" + sequence.to_bytes(2, "little") + bytes((16, 0, 0, 0))
        client.sendto(packet, peer)
        sequence += 1
        try:
            data, _ = client.recvfrom(600)
        except socket.timeout:
            pass
        else:
            if data[:4] == b"IL\x02\x02" and len(data) == 472:
                snapshot_seen = True
                assert data[6] == 0, "versus mode changed in the snapshot"
                laser_seen |= data[19] > 0
                jingle_seen |= data[23] > 0
        time.sleep(0.016)
    client.sendto(b"IL\x02\x03", peer)
    client.sendto(b"IL\x02\x03", peer)

assert snapshot_seen, "no complete LAN snapshot received"
assert jingle_seen, "connection sound event missing"
assert laser_seen, "laser sound event missing after guest fired"

with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
    client.settimeout(0.008)
    deadline = time.monotonic() + 1.0
    fresh_guest_seen = False
    sequence = 0
    while time.monotonic() < deadline and not fresh_guest_seen:
        packet = b"IL\x02\x01" + sequence.to_bytes(2, "little") + bytes((0, 2, 0, 0))
        client.sendto(packet, peer)
        sequence += 1
        try:
            data, _ = client.recvfrom(600)
        except socket.timeout:
            pass
        else:
            if data[:4] == b"IL\x02\x02" and len(data) == 472:
                fresh_guest_seen = data[40] == 3 and data[43] == 2 and data[19] == 0
        time.sleep(0.016)

assert fresh_guest_seen, "new guest inherited the previous guest's ship or match state"
print("LAN sound events and guest handoff passed")
