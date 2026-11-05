import json
import socket
import struct
import time
from pathlib import Path

HOST = "127.0.0.1"
PORT = 7777
ACK = b"GAMEPAD_ACK"


def main() -> None:
    clients = json.loads(Path(r"E:\Gamepad\paired_clients.json").read_text())
    token_hex = next(iter(clients))
    token = bytes.fromhex(token_hex)
    print("token", token_hex)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", 0))
    sock.settimeout(0.02)

    seq = 0
    acks = 0
    start = time.time()
    for index in range(10):
        packet = struct.pack("<HbbbbBB", 1 if index % 2 == 0 else 0, 0, 0, 0, 0, seq, 0)
        seq = (seq + 1) & 0xFF
        sock.sendto(packet + token, (HOST, PORT))
        deadline = time.time() + 0.4
        while time.time() < deadline:
            try:
                data, addr = sock.recvfrom(256)
            except socket.timeout:
                continue
            if data == ACK:
                acks += 1
                print(f"ack {acks} at t={time.time() - start:.2f}s from {addr}")
    print("total acks", acks)
    neutral = struct.pack("<HbbbbBB", 0, 0, 0, 0, 0, seq, 0)
    sock.sendto(neutral + token, (HOST, PORT))
    sock.close()


if __name__ == "__main__":
    main()
