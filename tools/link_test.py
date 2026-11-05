import ctypes
import json
import socket
import struct
import time
from pathlib import Path

HOST = "127.0.0.1"
PORT = 7777


class Gamepad(ctypes.Structure):
    _fields_ = [
        ("wButtons", ctypes.c_ushort),
        ("bLeftTrigger", ctypes.c_ubyte),
        ("bRightTrigger", ctypes.c_ubyte),
        ("sThumbLX", ctypes.c_short),
        ("sThumbLY", ctypes.c_short),
        ("sThumbRX", ctypes.c_short),
        ("sThumbRY", ctypes.c_short),
    ]


class State(ctypes.Structure):
    _fields_ = [("dwPacketNumber", ctypes.c_ulong), ("Gamepad", Gamepad)]


def read_pad() -> str:
    dll = ctypes.windll.xinput1_4
    out = []
    for slot in range(4):
        state = State()
        if dll.XInputGetState(slot, ctypes.byref(state)) == 0:
            out.append(f"slot{slot}=0x{state.Gamepad.wButtons:04X}")
    return " ".join(out) or "no pad"


def main() -> None:
    clients = json.loads(Path(r"E:\Gamepad\paired_clients.json").read_text())
    token_hex = next(iter(clients))
    token = bytes.fromhex(token_hex)
    print("token", token_hex)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", 0))
    sock.settimeout(0.1)

    packet = struct.pack("<HbbbbBB", 1 << 0, 0, 0, 0, 0, 20, 0) + token
    sock.sendto(packet, (HOST, PORT))
    print("sent v2 A, pad before:", read_pad())
    time.sleep(0.4)
    print("pad after 0.4s:", read_pad())

    deadline = time.time() + 4
    ack = False
    while time.time() < deadline:
        try:
            data, addr = sock.recvfrom(256)
        except socket.timeout:
            continue
        text = data.decode("utf-8", "replace")
        print("recv", text, "from", addr)
        if text == "GAMEPAD_ACK":
            ack = True
            break
    print("ack?", ack)

    legacy = struct.pack("<HbbbbBx", 1 << 0, 0, 0, 0, 0, 21)
    print("legacy bytes", len(legacy), legacy.hex())
    sock.sendto(legacy, (HOST, PORT))
    time.sleep(0.5)
    print("pad after legacy A:", read_pad())

    neutral = struct.pack("<HbbbbBx", 0, 0, 0, 0, 0, 22)
    sock.sendto(neutral, (HOST, PORT))
    sock.close()


if __name__ == "__main__":
    main()
