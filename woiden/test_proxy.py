#!/usr/bin/env python3
"""Test local SOCKS5 CONNECT to an IPv4-only destination via NAT64."""
import socket
import struct

with socket.create_connection(("127.0.0.1", 1080), 5) as s:
    s.settimeout(15)
    s.sendall(b"\x05\x01\x00")
    greeting = s.recv(2)
    if greeting != b"\x05\x00":
        raise SystemExit(f"SOCKS5 greeting FAILED: {greeting!r}")
    s.sendall(b"\x05\x01\x00\x01" + socket.inet_aton("1.1.1.1") + struct.pack("!H", 443))
    reply = s.recv(10)
    if len(reply) < 2 or reply[1] != 0:
        raise SystemExit(f"SOCKS5 NAT64 CONNECT FAILED: {reply!r}")
    print("SOCKS5 -> NAT64 -> 1.1.1.1:443 OK")
