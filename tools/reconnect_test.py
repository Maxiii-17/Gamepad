import ctypes
import json
import socket
import struct
import time
from pathlib import Path

HOST = "127.0.0.1"
PORT = 7777
HELLO = b"GAMEPAD_HELLO "
READY = b"GAMEPAD_READY"
ACK = b"GAMEPAD_ACK"


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


def main() -> None:
    time.sleep(1.2)
    token_hex = next(iter(json.loads(Path(r"E:\Gamepad\paired_clients.json").read_text())))
    print("stored token:", token_hex)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", 0))
    sock.settimeout(2.0)
    sock.sendto(HELLO + token_hex.encode(), (HOST, PORT))
    print("reconnect:", sock.recvfrom(128)[0].decode())

    packet = struct.pack("<HbbbbBB", 1 << 0, 0, 0, 0, 0, 1, 0) + bytes.fromhex(token_hex)
    sock.sendto(packet, (HOST, PORT))
    time.sleep(0.4)
    dll = ctypes.windll.xinput1_4
    state = State()
    slot = next(
        (index for index in range(4) if dll.XInputGetState(index, ctypes.byref(state)) == 0),
        -1,
    )
    print(f"after restart A: slot={slot} buttons=0x{state.Gamepad.wButtons:04X}")

    deadline = time.time() + 3
    while time.time() < deadline:
        data, _ = sock.recvfrom(64)
        if data == ACK:
            print("ack: received")
            break
    else:
        print("ack: MISSING")

    neutral = struct.pack("<HbbbbBB", 0, 0, 0, 0, 0, 2, 0) + bytes.fromhex(token_hex)
    sock.sendto(neutral, (HOST, PORT))
    sock.close()


if __name__ == "__main__":
    main()
