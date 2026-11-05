# Gamepad

A standalone Android gamepad for PC. Pair it with a 6-digit code (like AnyDesk),
then it drives a virtual Xbox 360 controller for PCSX2 or any XInput game.

**PhonePad 1 (`E:\Consloe`) is untouched** — Gamepad is a separate app with its
own package (`com.phonepad.gamepad`) and its own server.

---

## What's included

| File / Folder | Purpose |
|---|---|
| `Gamepad.apk` | Install this on the phone (release build, debug-signed) |
| `server.py` | PC side: pairing + UDP bridge to a virtual Xbox 360 pad |
| `start-server.bat` | One-click launcher for the server |
| `setup_firewall.ps1` | Allow UDP 7777 through Windows Firewall (run once, as admin) |
| `requirements.txt` | Python dependencies for the server |
| `tools\ViGEmBus_1.22.0_x64_x86_arm64.exe` | Virtual gamepad driver for Windows |
| `tools\set-env.ps1` | Sets JAVA/Android/Flutter env vars for building |
| `SECOND_EDITION_BLUEPRINT.md` | Design notes |
| `lib\` | Flutter app source |
| `test\` | Widget tests |

---

## Quick start (5 minutes)

### 1. PC — install the virtual gamepad driver (once)
Run `tools\ViGEmBus_1.22.0_x64_x86_arm64.exe` and follow the installer.

### 2. PC — open the firewall (once, as Administrator)
```powershell
powershell -ExecutionPolicy Bypass -File .\setup_firewall.ps1
```

### 3. PC — start the server
Double-click `start-server.bat` (or run it from a terminal). A window opens with
a code:

```text
======================================================================
  GAMEPAD PAIR CODE:  123 456    (valid 299 s)
======================================================================
Listening on udp://0.0.0.0:7777
```

Keep this window open. The code rotates every ~5 minutes; if it changes, use the
new one.

### 4. Phone — install the app
Copy `Gamepad.apk` to the phone and install it (allow "install from unknown
sources" when prompted). It installs as a **separate app** named **Gamepad**.

### 5. Phone — pair
1. Open **Gamepad**.
2. Type the 6-digit code shown on the PC.
3. Tap **Pair**.

The app switches to the pad and starts sending. The PC prints
`Paired Gamepad: <phone-ip>`.

### 6. PCSX2
In PCSX2: **Pad 1 → XInput → Xbox 360 Controller for Windows**.

From now on, opening Gamepad on the same network reconnects automatically.

---

## Features

- **Pair-code connection** — no IP typing. The PC shows a 6-digit code once.
- **Auto reconnect** — the phone remembers a private pairing token.
- **Keep screen awake** while the pad is open.
- **L3 / R3 / PS (Guide)** buttons.
- **Turbo** — tap TURBO; held face buttons and L1/R1 pulse ~7-8 times/sec.
- **Custom layout** — tap LAYOUT, drag any cluster, tap a cluster then use the
  slider to resize, **Reset all** to restore defaults, **Done** to save.
- **Status strip** — Sending / No reply / Socket error.

---

## Custom layout

Tap **LAYOUT** in the center panel:

- Drag shoulders, D-pad, sticks, face buttons, or the center panel.
- Tap a cluster, then use the slider to resize it (70 % – 135 %).
- **Reset all** restores the default layout.
- **Done** saves it. The layout survives app restarts.

---

## Pair-code details

- `paircode.txt` stores the code, so it stays the same across server restarts.
- `paired_clients.json` stores the tokens issued to phones.
- To rotate the code and forget all phones: stop the server, delete both files,
  then start it again.
- Gamepad packets add an extra feature byte (PS/Guide) and a 64-bit paired
  token on top of the original 8-byte input layout.

---

## Troubleshooting

- **Both devices must be on the same Wi-Fi** or the phone's hotspot.
- **Only one server can own UDP 7777.** Stop the PhonePad 1 server before
  starting `start-server.bat`, and vice versa.
- **Firewall:** allow inbound UDP 7777 with `setup_firewall.ps1` (as admin).
- **Status in the center panel:**
  - **Sending** — PC is acknowledging packets.
  - **No reply** — no ACK for a few seconds; check the server window.
  - **Socket error** — the phone could not open UDP; pair again.
- **Code expired?** The code rotates every ~5 minutes; use the current one.
- **Wrong code entered 5 times** rotates the code automatically.

---

## Running the server manually

If `start-server.bat` does not work, run it by hand:

```powershell
# optional: create a venv (once)
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt

# run
.\.venv\Scripts\python.exe server.py
```

Or reuse an existing venv, e.g. from PhonePad 1:

```powershell
D:\Project of console\Consloe\.venv\Scripts\python.exe D:\Project of console\Gamepad\server.py
```

---

## Building from source (optional)

Requirements: Flutter (D:\Program File\flutter), JDK 21, Android SDK.

```powershell
# set env (or run tools\set-env.ps1)
$env:JAVA_HOME = 'D:\Android\jdk-21'
$env:ANDROID_HOME = 'D:\Android\Sdk'
$env:PUB_CACHE = 'D:\Android\pub-cache'
$env:TEMP = 'D:\Android\tmp'

flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The release APK lands in `build\app\outputs\flutter-apk\app-release.apk`.

---

## Notes

- Gamepad and PhonePad 1 can both be installed; they use different package names.
- The layout is stored per phone in SharedPreferences, not synced to the PC.
- Source on D: because the E: drive was not available during recreation; move
  the folder freely if needed.
PY