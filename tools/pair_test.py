import ctypes
import socket
import struct
import time
from pathlib import Path

HOST = "127.0.0.1"
PORT = 7777
PREFIX = b"GAMEPAD_PAIR "
HELLO = b"GAMEPAD_HELLO "
PAIRED = b"GAMEPAD_PAIRED "
READY = b"GAMEPAD_READY"
BAD = b"GAMEPAD_BAD_CODE"
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


def xinput_buttons() -> tuple[int, int]:
    dll = ctypes.windll.xinput1_4
    for slot in range(4):
        state = State()
        if dll.XInputGetState(slot, ctypes.byref(state)) == 0:
            return slot, state.Gamepad.wButtons
    return -1, 0


def recv_text(sock: socket.socket, timeout: float = 2.0) -> str:
    sock.settimeout(timeout)
    data, _ = sock.recvfrom(256)
    return data.decode("utf-8", "replace")


def open_socket() -> socket.socket:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", 0))
    return sock


def send_input(
    sock: socket.socket,
    token: bytes,
    buttons: int,
    seq: int,
    extra: int = 0,
    paired: bool = True,
) -> None:
    packet = struct.pack("<HbbbbBB", buttons, 0, 0, 0, 0, seq, extra)
    if paired:
        packet += token
    sock.sendto(packet, (HOST, PORT))


def main() -> None:
    time.sleep(1.5)
    code = Path(r"E:\Gamepad\paircode.txt").read_text(encoding="ascii").strip()
    print(f"pair code: {code}")

    wrong = open_socket()
    wrong.sendto(PREFIX + b"000000", (HOST, PORT))
    print("wrong code reply:", recv_text(wrong))
    wrong.close()

    pair = open_socket()
    pair.sendto(PREFIX + code.encode("ascii"), (HOST, PORT))
    reply = recv_text(pair)
    assert reply.startswith(PAIRED.decode()), reply
    token_hex = reply[len(PAIRED) :].strip()
    token = bytes.fromhex(token_hex)
    print("paired token:", token_hex)
    pair.close()

    hello = open_socket()
    hello.sendto(HELLO + token_hex.encode("ascii"), (HOST, PORT))
    print("hello reply:", recv_text(hello))
    hello.close()

    control = open_socket()
    seq = 0

    def press(name: str, buttons: int, extra: int = 0) -> None:
        nonlocal seq
        send_input(control, token, buttons, seq, extra)
        seq = (seq + 1) & 0xFF
        time.sleep(0.25)
        slot, mask = xinput_buttons()
        print(f"{name}: slot={slot} buttons=0x{mask:04X}")
        time.sleep(0.15)

    press("A", 1 << 0)
    press("L1", 1 << 4)
    press("L3", 1 << 10)
    press("R3", 1 << 11)
    press("START", 1 << 9)
    press("PS/guide", 0, 1)
    press("neutral", 0)

    send_input(control, token, 1 << 0, seq)
    seq = (seq + 1) & 0xFF
    control.settimeout(3.0)
    try:
        while True:
            reply = control.recvfrom(64)[0].decode("utf-8", "replace")
            if reply == ACK:
                print("ack: received")
                break
    except socket.timeout:
        print("ack: TIMEOUT")

    bad = b"\x00\x00\x00\x00"
    send_input(control, bad, 1 << 0, seq)
    seq = (seq + 1) & 0xFF
    time.sleep(0.3)
    _, mask = xinput_buttons()
    print(f"bad token ignored: buttons=0x{mask:04X}")

    legacy = open_socket()
    legacy.sendto(struct.pack("<HbbbbBx", 1 << 0, 0, 0, 0, 0, seq), (HOST, PORT))
    time.sleep(0.3)
    _, mask = xinput_buttons()
    print(f"legacy A: buttons=0x{mask:04X}")
    legacy.close()

    send_input(control, token, 0, (seq + 1) & 0xFF)
    control.close()


if __name__ == "__main__":
    main()
