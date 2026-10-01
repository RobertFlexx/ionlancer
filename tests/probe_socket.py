#!/usr/bin/env python3
"""Exercise the UDP bridge's trust boundary without the game simulation."""
import ctypes
import socket
import sys
import time

bridge = ctypes.CDLL(sys.argv[1])
bridge.ion_lan_recv.argtypes = [ctypes.c_void_p, ctypes.c_int]
bridge.ion_lan_send.argtypes = [ctypes.c_void_p, ctypes.c_int]
buffer = ctypes.create_string_buffer(600)
port = 37178
peer = ("127.0.0.1", port)
valid = b"IL\x03\x01\x01\x00\x00\x02\x00\x01"


def receive(capacity=600):
    deadline = time.monotonic() + 0.2
    while time.monotonic() < deadline:
        n = bridge.ion_lan_recv(buffer, capacity)
        if n:
            return buffer.raw[:n]
        time.sleep(0.001)
    return b""


assert bridge.ion_lan_open(1, 127, 0, 0, 1, port) == 1
bridge.ion_lan_set_mode(1)
try:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as attacker, \
            socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as guest:
        attacker.settimeout(0.2)
        malformed = [b"", b"IL", b"IL\x02\x01" + valid[4:], valid + b"x",
                     valid + b"x" * 1400, b"IL\x03\x03x", b"IL\x03\x03"]
        for offset, value in ((6, 128), (7, 5), (8, 7), (9, 2)):
            packet = bytearray(valid)
            packet[offset] = value
            malformed.append(packet)
        for packet in malformed:
            attacker.sendto(packet, peer)
        guest.sendto(valid, peer)
        assert receive() == valid, "junk traffic blocked or claimed the valid guest"
        attacker.sendto(b"IL\x03\x03", peer)
        guest.sendto(valid, peer)
        assert receive() == valid, "an unrelated socket disconnected the guest"
        guest.sendto(b"IL\x03\x03x", peer)
        guest.sendto(valid, peer)
        assert receive() == valid, "a padded close packet was accepted"
        bridge.ion_lan_release_peer(0)
        mismatch = valid[:-1] + b"\x00"
        attacker.sendto(mismatch, peer)
        guest.sendto(valid, peer)
        assert receive() == valid, "wrong mode occupied the host peer slot"
        assert attacker.recvfrom(600)[0] == b"IL\x03\x04\x01"
        bridge.ion_lan_release_peer(1)
        guest.sendto(valid, peer)
        assert receive() == valid, "same-address reconnect was rejected"
finally:
    bridge.ion_lan_close()

# A datagram larger than the caller's buffer must never be accepted as a prefix.
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as host:
    host.bind(peer)
    assert bridge.ion_lan_open(0, 127, 0, 0, 1, port) == 1
    bridge.ion_lan_send(valid, len(valid))
    _, guest_address = host.recvfrom(600)
    snapshot = b"IL\x03\x02" + bytes(468)
    host.sendto(snapshot + b"padding", guest_address)
    host.sendto(snapshot, guest_address)
    assert receive(472) == snapshot, "truncated snapshot prefix was accepted"
    bridge.ion_lan_close()

print("UDP malformed lengths, bounds, peer isolation, lobby mode, and truncation passed")
