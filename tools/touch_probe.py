import ctypes
import subprocess
import sys
import time

ADB = r"D:\Android\Sdk\platform-tools\adb.exe"


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
    if len(sys.argv) != 4:
        print("usage: touch_probe.py X Y HOLD_MS")
        raise SystemExit(2)

    x, y, hold = (int(value) for value in sys.argv[1:])
    dll = ctypes.windll.xinput1_4

    slot = -1
    for index in range(4):
        state = State()
        if dll.XInputGetState(index, ctypes.byref(state)) == 0:
            slot = index
            break
    if slot < 0:
        print("no XInput pad")
        raise SystemExit(1)

    proc = subprocess.Popen(
        [ADB, "shell", "input", "swipe", str(x), str(y), str(x), str(y), str(hold)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    start = time.time()
    last = None
    seen = []
    while time.time() - start < hold / 1000 + 1.0:
        state = State()
        if dll.XInputGetState(slot, ctypes.byref(state)) == 0:
            mask = state.Gamepad.wButtons
            if mask != last:
                seen.append((round(time.time() - start, 3), mask))
                last = mask
        time.sleep(0.01)

    proc.wait(timeout=5)
    for when, mask in seen:
        print(f"{when:6.3f}s  0x{mask:04X}")
    print("distinct:", ", ".join(f"0x{mask:04X}" for _, mask in seen))


if __name__ == "__main__":
    main()
