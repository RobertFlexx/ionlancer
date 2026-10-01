#!/usr/bin/env python3
"""Check that a firing guest gets v3 snapshots with gameplay sound events."""

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
        packet = b"IL\x03\x01" + sequence.to_bytes(2, "little") + bytes((16, 0, 0, 0))
        client.sendto(packet, peer)
        sequence += 1
        try:
            data, _ = client.recvfrom(600)
        except socket.timeout:
            pass
        else:
            if data[:4] == b"IL\x03\x02" and len(data) == 472:
                snapshot_seen = True
                assert data[6] == 0, "versus mode changed in the snapshot"
                laser_seen |= data[19] > 0
                jingle_seen |= data[23] > 0
        time.sleep(0.016)
    client.sendto(b"IL\x03\x03", peer)
    client.sendto(b"IL\x03\x03", peer)

assert snapshot_seen, "no complete LAN snapshot received"
assert jingle_seen, "connection sound event missing"
assert laser_seen, "laser sound event missing after guest fired"

with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
    client.settimeout(0.008)
    deadline = time.monotonic() + 1.0
    fresh_guest_seen = False
    sequence = 0
    while time.monotonic() < deadline and not fresh_guest_seen:
        packet = b"IL\x03\x01" + sequence.to_bytes(2, "little") + bytes((0, 2, 0, 0))
        client.sendto(packet, peer)
        sequence += 1
        try:
            data, _ = client.recvfrom(600)
        except socket.timeout:
            pass
        else:
            if data[:4] == b"IL\x03\x02" and len(data) == 472:
                fresh_guest_seen = data[40] == 3 and data[43] == 2 and data[19] == 0
        time.sleep(0.016)

    def exchange(mask, seq=None, duration=0.2, ship=2):
        global sequence
        frames = []
        until = time.monotonic() + duration
        while time.monotonic() < until:
            number = sequence if seq is None else seq
            client.sendto(b"IL\x03\x01" + (number % 65536).to_bytes(2, "little") +
                          bytes((mask, ship, 0, 0)), peer)
            if seq is None:
                sequence += 1
            try:
                data, _ = client.recvfrom(600)
                if data[:4] == b"IL\x03\x02" and len(data) == 472:
                    frames.append(data)
            except socket.timeout:
                pass
            time.sleep(0.016)
        return frames

    paused = exchange(64)
    assert paused and paused[-1][7] & 2, "guest pause was not shared"
    paused_clock = paused[-1][14:16]
    replay_sequence = sequence - 1
    replayed = exchange(0, seq=replay_sequence, duration=4.4)
    assert replayed and all(data[7] & 2 for data in replayed), "replayed input resumed a paused match"
    assert all(data[14:16] == paused_clock for data in replayed), "clock advanced during shared pause"
    assert not exchange(0, seq=replay_sequence, duration=0.25), "replays kept the peer alive past timeout"

    # Resume the same running session from a new UDP source port. Its chosen
    # loadout and match state must survive, even if the new packet advertises
    # another ship. Ship/modifier selection is fixed at the initial connection.
    previous_client = client
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        client.settimeout(0.008)
        resumed = exchange(0, duration=0.35, ship=4)
        assert resumed, "same-pilot reconnect from a new source port failed"
        assert resumed[-1][43] == 2, "reconnect replaced the existing pilot's ship"
        assert not resumed[-1][7] & 2, "match did not resume after reconnect"
        assert int.from_bytes(resumed[-1][14:16], "little") <= int.from_bytes(paused_clock, "little")
        client.sendto(b"IL\x03\x03", peer)
    client = previous_client

assert fresh_guest_seen, "new guest inherited the previous guest's ship or match state"
print("LAN sounds, guest handoff, shared pause, replay timeout, and reconnect passed")
