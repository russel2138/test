#!/usr/bin/env python3
"""Loopback-only SOCKS5 TCP relay translating IPv4 targets through DNS64/NAT64."""
import ipaddress
import select
import socket
import socketserver
import struct
import sys

BIND = "127.0.0.1"
PORT = 1080
PREFIX = None


def discover_prefix():
    # RFC 7050: discover the /96 prefix using 192.0.0.170 and .171.
    markers = {ipaddress.IPv4Address(v).packed for v in ("192.0.0.170", "192.0.0.171")}
    results = socket.getaddrinfo("ipv4only.arpa", None, family=socket.AF_INET6,
                                  type=socket.SOCK_STREAM)
    for entry in results:
        packed = ipaddress.IPv6Address(entry[4][0]).packed
        if packed[12:] in markers:
            return packed[:12]
    raise RuntimeError("DNS64 /96 prefix not discovered from ipv4only.arpa")


def recvn(sock, size):
    data = bytearray()
    while len(data) < size:
        part = sock.recv(size - len(data))
        if not part:
            raise EOFError("client disconnected")
        data.extend(part)
    return bytes(data)


def candidates(host, port, kind):
    if kind == 1:
        address = str(ipaddress.IPv6Address(PREFIX + ipaddress.IPv4Address(host).packed))
        return [(socket.AF_INET6, socket.SOCK_STREAM, 0, "", (address, port, 0, 0))]
    return socket.getaddrinfo(host, port, family=socket.AF_INET6, type=socket.SOCK_STREAM)


def connect_v6(host, port, kind):
    last_error = None
    for af, socktype, proto, _, address in candidates(host, port, kind):
        remote = socket.socket(af, socktype, proto)
        remote.settimeout(12)
        try:
            remote.connect(address)
            remote.settimeout(None)
            return remote
        except OSError as exc:
            last_error = exc
            remote.close()
    raise last_error or OSError("no reachable IPv6/NAT64 address")


def relay(left, right):
    opened = [left, right]
    while opened:
        ready, _, _ = select.select(opened, [], [])
        for source in ready:
            dest = right if source is left else left
            data = source.recv(32768)
            if data:
                dest.sendall(data)
            else:
                opened.remove(source)
                try:
                    dest.shutdown(socket.SHUT_WR)
                except OSError:
                    pass


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        client = self.request
        client.settimeout(15)
        try:
            ver, count = struct.unpack("!BB", recvn(client, 2))
            methods = recvn(client, count)
            if ver != 5 or not count or 0 not in methods:
                client.sendall(b"\x05\xff")
                return
            client.sendall(b"\x05\x00")
            ver, cmd, reserved, atyp = struct.unpack("!BBBB", recvn(client, 4))
            if ver != 5 or cmd != 1 or reserved != 0:
                client.sendall(b"\x05\x07\x00\x01" + b"\x00" * 6)
                return
            if atyp == 1:
                host = socket.inet_ntop(socket.AF_INET, recvn(client, 4))
            elif atyp == 3:
                host = recvn(client, recvn(client, 1)[0]).decode("idna")
            elif atyp == 4:
                host = socket.inet_ntop(socket.AF_INET6, recvn(client, 16))
            else:
                client.sendall(b"\x05\x08\x00\x01" + b"\x00" * 6)
                return
            port = struct.unpack("!H", recvn(client, 2))[0]
            if not port:
                client.sendall(b"\x05\x01\x00\x01" + b"\x00" * 6)
                return
            try:
                remote = connect_v6(host, port, atyp)
            except Exception as exc:
                print(f"[nat64] CONNECT {host}:{port} FAILED: {exc}", flush=True)
                client.sendall(b"\x05\x05\x00\x01" + b"\x00" * 6)
                return
            with remote:
                client.sendall(b"\x05\x00\x00\x01" + b"\x00" * 6)
                client.settimeout(None)
                print(f"[nat64] CONNECT {host}:{port} OK", flush=True)
                relay(client, remote)
        except (EOFError, OSError, ValueError, UnicodeError) as exc:
            print(f"[nat64] connection ended: {exc}", flush=True)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
    block_on_close = False


if __name__ == "__main__":
    try:
        PREFIX = discover_prefix()
    except Exception as exc:
        sys.exit(f"[nat64] Unable to discover NAT64 /96 prefix: {exc}")
    print("[nat64] DNS64 prefix: " + str(ipaddress.IPv6Address(PREFIX + b"\x00" * 4)) + "/96", flush=True)
    print(f"[nat64] SOCKS5 TCP CONNECT listening on {BIND}:{PORT}", flush=True)
    with Server((BIND, PORT), Handler) as server:
        server.serve_forever()
