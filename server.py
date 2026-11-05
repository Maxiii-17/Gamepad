#!/usr/bin/env python3
"""Gamepad server.

Receives 8-byte legacy packets from PhonePad 1 and 12-byte paired packets from
Gamepad. Both drive one virtual Xbox 360 controller.

Gamepad pairing:
  phone -> GAMEPAD_PAIR <6 digits>
  pc    -> GAMEPAD_PAIRED <8 hex token>
  phone -> GAMEPAD_HELLO <token>       (reconnect)
  pc    -> GAMEPAD_READY
  phone -> 8 input bytes + 4-byte token  (normal input)
  pc    -> GAMEPAD_ACK                 (roughly once per second)
"""

from __future__ import annotations

import asyncio
import errno
import json
import secrets
import socket
import struct
import sys
from pathlib import Path
from typing import Final

HOST: Final[str] = "0.0.0.0"
PORT: Final[int] = 7777
IDLE_TIMEOUT: Final[float] = 2.0
PACKET_SIZE: Final[int] = 8
PAIRED_PACKET_SIZE: Final[int] = 16

DISCOVERY_REQUEST: Final[bytes] = b"PHONEPAD_DISCOVER_V1"
DISCOVERY_ANNOUNCE: Final[bytes] = b"PHONEPAD_SERVER_V1"
PAIR_PREFIX: Final[bytes] = b"GAMEPAD_PAIR "
HELLO_PREFIX: Final[bytes] = b"GAMEPAD_HELLO "
PAIRED_PREFIX: Final[bytes] = b"GAMEPAD_PAIRED "
READY_REPLY: Final[bytes] = b"GAMEPAD_READY"
BAD_CODE_REPLY: Final[bytes] = b"GAMEPAD_BAD_CODE"
ACK_REPLY: Final[bytes] = b"GAMEPAD_ACK"
ANNOUNCE_INTERVAL: Final[float] = 2.0
TOKEN_BYTES: Final[int] = 8
MAX_PAIRED_CLIENTS: Final[int] = 8
ALLOW_LEGACY: Final[bool] = "--allow-legacy" in sys.argv

BTN_CROSS = 1 << 0
BTN_CIRCLE = 1 << 1
BTN_SQUARE = 1 << 2
BTN_TRIANGLE = 1 << 3
BTN_L1 = 1 << 4
BTN_R1 = 1 << 5
BTN_L2 = 1 << 6
BTN_R2 = 1 << 7
BTN_SELECT = 1 << 8
BTN_START = 1 << 9
BTN_L3 = 1 << 10
BTN_R3 = 1 << 11
BTN_UP = 1 << 12
BTN_DOWN = 1 << 13
BTN_LEFT = 1 << 14
BTN_RIGHT = 1 << 15
BTN_PS = 1 << 16


def _axis(value: int) -> int:
    return max(-127, min(127, value)) * 257


class GamepadBackend:
    def update(self, buttons: int, lx: int, ly: int, rx: int, ry: int) -> None:
        raise NotImplementedError

    def neutral(self) -> None:
        self.update(0, 0, 0, 0, 0)

    def close(self) -> None:
        pass


class WindowsBackend(GamepadBackend):
    def __init__(self) -> None:
        import vgamepad as vg

        self._pad = vg.VX360Gamepad()
        self._button_map = (
            (BTN_CROSS, vg.XUSB_BUTTON.XUSB_GAMEPAD_A),
            (BTN_CIRCLE, vg.XUSB_BUTTON.XUSB_GAMEPAD_B),
            (BTN_SQUARE, vg.XUSB_BUTTON.XUSB_GAMEPAD_X),
            (BTN_TRIANGLE, vg.XUSB_BUTTON.XUSB_GAMEPAD_Y),
            (BTN_L1, vg.XUSB_BUTTON.XUSB_GAMEPAD_LEFT_SHOULDER),
            (BTN_R1, vg.XUSB_BUTTON.XUSB_GAMEPAD_RIGHT_SHOULDER),
            (BTN_SELECT, vg.XUSB_BUTTON.XUSB_GAMEPAD_BACK),
            (BTN_START, vg.XUSB_BUTTON.XUSB_GAMEPAD_START),
            (BTN_L3, vg.XUSB_BUTTON.XUSB_GAMEPAD_LEFT_THUMB),
            (BTN_R3, vg.XUSB_BUTTON.XUSB_GAMEPAD_RIGHT_THUMB),
            (BTN_UP, vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_UP),
            (BTN_DOWN, vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_DOWN),
            (BTN_LEFT, vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_LEFT),
            (BTN_RIGHT, vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_RIGHT),
            (BTN_PS, vg.XUSB_BUTTON.XUSB_GAMEPAD_GUIDE),
        )
        self._last_buttons = -1

    def update(self, buttons: int, lx: int, ly: int, rx: int, ry: int) -> None:
        if buttons != self._last_buttons:
            for bit, code in self._button_map:
                if buttons & bit:
                    self._pad.press_button(code)
                else:
                    self._pad.release_button(code)
            self._last_buttons = buttons

        self._pad.left_joystick(_axis(lx), _axis(ly))
        self._pad.right_joystick(_axis(rx), _axis(ry))
        self._pad.left_trigger(255 if buttons & BTN_L2 else 0)
        self._pad.right_trigger(255 if buttons & BTN_R2 else 0)
        self._pad.update()


class LinuxBackend(GamepadBackend):
    def __init__(self) -> None:
        from evdev import AbsInfo, UInput, ecodes as e

        self._e = e
        self._button_map = (
            (BTN_CROSS, e.BTN_SOUTH),
            (BTN_CIRCLE, e.BTN_EAST),
            (BTN_SQUARE, e.BTN_WEST),
            (BTN_TRIANGLE, e.BTN_NORTH),
            (BTN_L1, e.BTN_TL),
            (BTN_R1, e.BTN_TR),
            (BTN_SELECT, e.BTN_SELECT),
            (BTN_START, e.BTN_START),
            (BTN_L3, e.BTN_THUMBL),
            (BTN_R3, e.BTN_THUMBR),
            (BTN_PS, e.BTN_MODE),
        )
        capabilities = {
            e.EV_KEY: [code for _, code in self._button_map],
            e.EV_ABS: [
                (e.ABS_X, AbsInfo(0, -32767, 32767, 0, 0, 0)),
                (e.ABS_Y, AbsInfo(0, -32767, 32767, 0, 0, 0)),
                (e.ABS_RX, AbsInfo(0, -32767, 32767, 0, 0, 0)),
                (e.ABS_RY, AbsInfo(0, -32767, 32767, 0, 0, 0)),
                (e.ABS_Z, AbsInfo(0, 0, 255, 0, 0, 0)),
                (e.ABS_RZ, AbsInfo(0, 0, 255, 0, 0, 0)),
                (e.ABS_HAT0X, AbsInfo(0, -1, 1, 0, 0, 0)),
                (e.ABS_HAT0Y, AbsInfo(0, -1, 1, 0, 0, 0)),
            ],
        }
        self._ui = UInput(capabilities, name="Gamepad Virtual Gamepad")
        self._last_buttons = -1

    def update(self, buttons: int, lx: int, ly: int, rx: int, ry: int) -> None:
        e = self._e
        if buttons != self._last_buttons:
            for bit, code in self._button_map:
                self._ui.write(e.EV_KEY, code, 1 if buttons & bit else 0)
            self._last_buttons = buttons

        hat_x = (1 if buttons & BTN_RIGHT else 0) - (1 if buttons & BTN_LEFT else 0)
        hat_y = (1 if buttons & BTN_DOWN else 0) - (1 if buttons & BTN_UP else 0)

        self._ui.write(e.EV_ABS, e.ABS_X, _axis(lx))
        self._ui.write(e.EV_ABS, e.ABS_Y, -_axis(ly))
        self._ui.write(e.EV_ABS, e.ABS_RX, _axis(rx))
        self._ui.write(e.EV_ABS, e.ABS_RY, -_axis(ry))
        self._ui.write(e.EV_ABS, e.ABS_Z, 255 if buttons & BTN_L2 else 0)
        self._ui.write(e.EV_ABS, e.ABS_RZ, 255 if buttons & BTN_R2 else 0)
        self._ui.write(e.EV_ABS, e.ABS_HAT0X, hat_x)
        self._ui.write(e.EV_ABS, e.ABS_HAT0Y, hat_y)
        self._ui.syn()

    def close(self) -> None:
        self._ui.close()


def _create_backend() -> GamepadBackend:
    if sys.platform == "win32":
        return WindowsBackend()
    if sys.platform.startswith("linux"):
        return LinuxBackend()
    raise RuntimeError(f"Unsupported platform: {sys.platform}")


def _lan_ipv4_addresses() -> list[str]:
    addresses: set[str] = set()
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("8.8.8.8", 80))
        addresses.add(probe.getsockname()[0])
    except OSError:
        pass
    finally:
        probe.close()

    try:
        for info in socket.getaddrinfo(
            socket.gethostname(), None, socket.AF_INET, socket.SOCK_DGRAM
        ):
            addresses.add(info[4][0])
    except OSError:
        pass

    return sorted(a for a in addresses if not a.startswith("127."))


class PairStore:
    """Stores the visible pair code and the tokens issued to phones."""

    def __init__(self, folder: Path) -> None:
        self._folder = folder
        self._code_path = folder / "paircode.txt"
        self._clients_path = folder / "paired_clients.json"
        self._code = self._load_or_create_code()
        self._clients = self._load_clients()

    @property
    def code(self) -> str:
        return self._code

    @property
    def display_code(self) -> str:
        return f"{self._code[:3]} {self._code[3:]}"

    def register(self, ip: str) -> str:
        token = secrets.token_hex(TOKEN_BYTES)
        self._clients[token] = ip
        while len(self._clients) > MAX_PAIRED_CLIENTS:
            self._clients.pop(next(iter(self._clients)))
        self._save_clients()
        return token

    def is_paired(self, token: str) -> bool:
        return token in self._clients

    def bind(self, token: str, ip: str) -> None:
        if self._clients.get(token) == ip:
            return
        self._clients[token] = ip
        self._save_clients()

    def _load_or_create_code(self) -> str:
        try:
            code = self._code_path.read_text(encoding="ascii").strip()
            if len(code) == 6 and code.isdigit():
                return code
        except OSError:
            pass

        code = f"{secrets.randbelow(900000) + 100000:06d}"
        try:
            self._folder.mkdir(parents=True, exist_ok=True)
            self._code_path.write_text(code + "\n", encoding="ascii")
        except OSError:
            pass
        return code

    def _load_clients(self) -> dict[str, str]:
        try:
            raw = json.loads(self._clients_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
        if not isinstance(raw, dict):
            return {}

        clients: dict[str, str] = {}
        for token, ip in raw.items():
            if (
                isinstance(token, str)
                and len(token) == TOKEN_BYTES * 2
                and isinstance(ip, str)
            ):
                try:
                    int(token, 16)
                except ValueError:
                    continue
                clients[token] = ip
        return clients

    def _save_clients(self) -> None:
        try:
            self._clients_path.write_text(
                json.dumps(self._clients, indent=2) + "\n",
                encoding="utf-8",
            )
        except OSError:
            pass


class DiscoveryBroadcaster:
    def __init__(self, port: int) -> None:
        self._port = port
        self._socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self._socket.setblocking(False)
        self._task: asyncio.Task[None] | None = None

    def start(self) -> None:
        self._task = asyncio.create_task(self._run())

    def close(self) -> None:
        if self._task is not None:
            self._task.cancel()
            self._task = None
        self._socket.close()

    async def _run(self) -> None:
        loop = asyncio.get_running_loop()
        targets = self._targets()
        refreshed = loop.time()
        while True:
            for host in targets:
                try:
                    self._socket.sendto(DISCOVERY_ANNOUNCE, (host, self._port))
                except OSError:
                    pass
            await asyncio.sleep(ANNOUNCE_INTERVAL)
            now = loop.time()
            if now - refreshed >= 30.0:
                targets = self._targets()
                refreshed = now

    def _targets(self) -> list[str]:
        targets = {"255.255.255.255"}
        for address in _lan_ipv4_addresses():
            parts = address.split(".")
            if len(parts) == 4:
                targets.add(".".join((*parts[:3], "255")))
        return sorted(targets)


class PhonePadProtocol(asyncio.DatagramProtocol):
    def __init__(
        self,
        backend: GamepadBackend,
        loop: asyncio.AbstractEventLoop,
        store: PairStore,
    ) -> None:
        self._backend = backend
        self._loop = loop
        self._store = store
        self._transport: asyncio.DatagramTransport | None = None
        self._last_seq: int | None = None
        self._last_time = 0.0
        self._timeout_handle: asyncio.TimerHandle | None = None
        self._ack_handle: asyncio.TimerHandle | None = None
        self._neutral = True
        self._client_ip: str | None = None
        self._client_addr: tuple[str, int] | None = None
        self._active_token: str | None = None

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self._transport = transport  # type: ignore[assignment]

    def datagram_received(self, data: bytes, addr: tuple[str, int]) -> None:
        if data == DISCOVERY_REQUEST:
            self._reply(DISCOVERY_ANNOUNCE, addr)
            return

        if data.startswith(PAIR_PREFIX):
            self._handle_pair(data[len(PAIR_PREFIX) :], addr)
            return

        if data.startswith(HELLO_PREFIX):
            self._handle_hello(data[len(HELLO_PREFIX) :], addr)
            return

        if len(data) == PAIRED_PACKET_SIZE:
            self._handle_input(data, addr, paired=True)
        elif len(data) == PACKET_SIZE and ALLOW_LEGACY:
            self._handle_input(data, addr, paired=False)

    def _handle_pair(self, raw_code: bytes, addr: tuple[str, int]) -> None:
        code = raw_code.decode("ascii", errors="ignore").strip()
        if code != self._store.code:
            print(f"Pair attempt with wrong code from {addr[0]}", flush=True)
            self._reply(BAD_CODE_REPLY, addr)
            return

        token = self._store.register(addr[0])
        self._reply(PAIRED_PREFIX + token.encode("ascii"), addr)
        print(f"Paired Gamepad: {addr[0]}", flush=True)

    def _handle_hello(self, raw_token: bytes, addr: tuple[str, int]) -> None:
        token = raw_token.decode("ascii", errors="ignore").strip().lower()
        if not self._store.is_paired(token):
            return
        self._store.bind(token, addr[0])
        self._reply(READY_REPLY, addr)

    def _handle_input(
        self,
        data: bytes,
        addr: tuple[str, int],
        *,
        paired: bool,
    ) -> None:
        token: str | None = None
        if paired:
            token = data[8:16].hex()
            if not self._store.is_paired(token):
                return

        buttons, lx, ly, rx, ry, seq, extended = struct.unpack(
            "<HbbbbBB", data[:8]
        )
        if extended & 0x01:
            buttons |= BTN_PS

        if token != self._active_token:
            self._active_token = token
            self._last_seq = None

        if self._last_seq is not None and ((seq - self._last_seq) & 0xFF) >= 128:
            return

        new_client = self._client_ip != addr[0]
        self._last_seq = seq
        self._last_time = self._loop.time()
        self._neutral = False
        self._client_ip = addr[0]
        self._client_addr = addr

        if new_client:
            label = "Gamepad" if paired else "PhonePad"
            print(f"{label} client: {addr[0]}", flush=True)

        self._store.bind(token, addr[0])
        self._backend.update(buttons, lx, ly, rx, ry)
        self._arm_timeout()
        if paired:
            self._schedule_ack()

    def _reply(self, message: bytes, addr: tuple[str, int]) -> None:
        if self._transport is not None and not self._transport.is_closing():
            self._transport.sendto(message, addr)

    def _schedule_ack(self) -> None:
        if self._ack_handle is not None:
            return
        self._ack_handle = self._loop.call_later(0.8, self._send_ack)

    def _send_ack(self) -> None:
        self._ack_handle = None
        if (
            self._transport is None
            or self._transport.is_closing()
            or self._neutral
            or self._client_addr is None
            or self._loop.time() - self._last_time > IDLE_TIMEOUT
        ):
            return
        self._transport.sendto(ACK_REPLY, self._client_addr)
        self._ack_handle = self._loop.call_later(1.0, self._send_ack)

    def _arm_timeout(self) -> None:
        if self._timeout_handle is not None:
            self._timeout_handle.cancel()
        self._timeout_handle = self._loop.call_later(IDLE_TIMEOUT, self._on_timeout)

    def _on_timeout(self) -> None:
        self._timeout_handle = None
        if self._transport is None or self._transport.is_closing():
            return

        remaining = IDLE_TIMEOUT - (self._loop.time() - self._last_time)
        if remaining > 0:
            self._timeout_handle = self._loop.call_later(remaining, self._on_timeout)
            return

        if not self._neutral:
            self._neutral = True
            self._last_seq = None
            self._backend.neutral()
            print("PhonePad idle: controller neutral", flush=True)

    def shutdown(self) -> None:
        if self._timeout_handle is not None:
            self._timeout_handle.cancel()
            self._timeout_handle = None
        if self._ack_handle is not None:
            self._ack_handle.cancel()
            self._ack_handle = None
        self._transport = None


async def _serve() -> None:
    store = PairStore(Path(__file__).resolve().parent)
    backend = _create_backend()
    transport: asyncio.DatagramTransport | None = None
    protocol: PhonePadProtocol | None = None
    broadcaster = DiscoveryBroadcaster(PORT)

    try:
        loop = asyncio.get_running_loop()
        try:
            transport, protocol = await loop.create_datagram_endpoint(
                lambda: PhonePadProtocol(backend, loop, store),
                local_addr=(HOST, PORT),
            )
        except OSError as exc:
            if getattr(exc, "winerror", None) == 10048 or exc.errno == errno.EADDRINUSE:
                print(
                    f"PhonePad is already running: UDP {PORT} is in use.",
                    flush=True,
                )
                print("Close the other server window and try again.", flush=True)
                return
            raise

        addresses = _lan_ipv4_addresses()
        print("=" * 54, flush=True)
        print(f"  GAMEPAD PAIR CODE:  {store.display_code}", flush=True)
        print("=" * 54, flush=True)
        print(f"Gamepad server listening on udp://{HOST}:{PORT}", flush=True)
        if addresses:
            print(f"LAN address: {', '.join(addresses)}", flush=True)
        print("Open Gamepad and enter the code above.", flush=True)
        if ALLOW_LEGACY:
            print("Legacy PhonePad 1 input is enabled.", flush=True)
        else:
            print("Pairing required; PhonePad 1 packets are ignored.", flush=True)
        broadcaster.start()
        await asyncio.Event().wait()
    finally:
        broadcaster.close()
        if protocol is not None:
            protocol.shutdown()
        if transport is not None:
            transport.close()
        try:
            backend.neutral()
        finally:
            backend.close()


def main() -> None:
    try:
        asyncio.run(_serve())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
