# Gamepad - Second Edition Blueprint

**Status:** draft for approval
**Target project:** `D:\Project of console\Consloe` (PhonePad 1 source)
**Original Second Edition:** `E:\PhonePad2` (deleted — design reconstructed from the conversation record)
**Date:** 2026-11-05

---

## 1. Purpose

This document recreates the **Second Edition blueprint** and adapts it to the current
Consloe project. The goal is to give Consloe the Second Edition's **custom layout
editor** (drag + resize + Reset all) while keeping the **v1 connection method**
(UDP 7777 auto-discovery, no pair code, no tokens, no HMAC).

---

## 2. History — how the Second Edition came to be

| Stage | Project | What it was |
|---|---|---|
| First edition | `E:\Consloe` | Simple 8-byte UDP gamepad: auto-pair + manual IPv4, fixed layout |
| Second edition | `E:\PhonePad2` | Separate copy of Consloe with pair-code connection, token reconnect, Turbo, L3/R3/PS, keep-awake, **custom layout editor** |
| Big upgrade | `E:\PhonePad3` → renamed `E:\PhonePad2` | Protocol v3: HMAC-SHA256 pairing, dynamic ports 7777–7787, 4 slots, analog triggers, rumble, link modes |
| Current | `D:\Project of console\Consloe` | Working copy of the first edition; this is what we upgrade now |

The Second Edition shipped as `2.2.0+4` and was documented in
`PhonePad2-Project-Summary.html` → `PhonePad2-Project-Summary.pdf` (4 pages).
Both the source and the PDF were deleted with `E:\PhonePad2`.
`E:\Consloe` was never modified and must not be touched.

---

## 3. Scope of this upgrade

### Adopted from the Second Edition
- Custom layout editor: drag every control cluster, tap to select, resize with a slider, Reset all.
- Layout saved per phone and restored on launch.
- Edit mode that disables gameplay input while arranging controls.

### Kept from Consloe v1
- UDP 7777, 8-byte input packet, `PHONEPAD_DISCOVER_V1` / `PHONEPAD_SERVER_V1` broadcast discovery.
- Manual IPv4 fallback via the Settings page.
- PC server (`server.py`) with ViGEm/Xbox 360 output.

### Added for usability (still v1 connection)
- Auto-connect on launch (saved IP first, discovery in parallel).
- Auto-retry while disconnected and reconnect on app resume.
- Status strip: Searching / Connected / Sending / No server.
- Optional latency (RTT) via an additive ACK from the server.

### Explicitly out of scope
- Pair codes, tokens, HMAC, dynamic ports, multi-pad, rumble, analog triggers.
- Turbo, L3/R3/PS buttons, keep-awake.
- Full Second Edition rebuild in a separate project.

---

## 4. Feature specification

### 4.1 Custom layout editor

#### Control clusters
| ID | Contents | Default x | Default y | Default scale |
|---|---|---|---|---|
| `shouldersLeft` | L1 + L2 | 0.115 | 0.10 | 1.00 |
| `dpad` | D-Pad | 0.105 | 0.60 | 1.00 |
| `leftStick` | Left analog stick | 0.295 | 0.60 | 1.00 |
| `center` | Status, Connect, LAYOUT, SEL/START | 0.500 | 0.55 | 1.00 |
| `rightStick` | Right analog stick | 0.705 | 0.60 | 1.00 |
| `face` | Cross/Circle/Square/Triangle | 0.895 | 0.60 | 1.00 |
| `shouldersRight` | R1 + R2 | 0.885 | 0.10 | 1.00 |

`x` and `y` are normalized **center** coordinates (0.0–1.0) of the screen.
`scale` is clamped to **0.70–1.35** (same range as the Second Edition).

#### Sizes
- Base cluster size is derived from the screen:
  `base = clamp(min(width * 0.12, height * 0.26), 96, 176)`.
- Actual size = `base * scale`.
- Shoulder pairs: width ≈ `base * 0.62` per button, height ≈ `base * 0.26`.
- Center panel: width ≈ `base * 0.95`, natural height.
- **Important:** implement resizing by giving the widget its real scaled size
  (not `Transform.scale`), so the touch area always matches what is drawn.

#### Edit mode
Entry: **LAYOUT** button in the center panel.
While edit mode is active:
- Gameplay input is disabled (`AbsorbPointer` / mode switch).
- Every cluster shows a subtle outline.
- Drag a cluster with one finger to move it.
- Tap a cluster to select it; the selected cluster gets an accent outline.
- A bottom toolbar shows:
  - selected cluster name,
  - a **size slider** (70 %–135 %),
  - **Reset all**,
  - **Done**.
- Movement snaps to 0.5 % steps and is clamped so the cluster stays fully on screen
  with an 8 px margin.
- Overlap is allowed (user choice), but clusters cannot leave the screen.

#### Persistence
- Saved to `SharedPreferences` under `pad_layout_v1` as JSON:
  `{"dpad":[0.105,0.60,1.0], ...}`.
- Save triggers: end of drag, end of slider drag, Done, Reset all.
- Corrupt or missing data → fall back to defaults.
- Reset all restores the table above and saves immediately.

#### Normal mode
- The layout is applied on every build (default or saved).
- All touch logic stays exactly as today (Listener-based multi-touch).

### 4.2 Connection (v1 method)

- **Launch with saved IP:** connect immediately, run discovery in the background.
- **Launch without IP:** discovery with a 4 s window, retry every 3 s.
- **On resume:** rebind the UDP socket, restart the heartbeat, re-discover.
- **While disconnected:** silent retry every 5 s.
- **Manual fallback:** gear icon → existing Settings page (IPv4 entry + Find automatically).
- **Status:**
  - `Searching` — discovery running (blue, spinner).
  - `Connected` — server announcement seen within 5 s (green).
  - `Sending (no reply)` — socket open but no announcement/ACK (amber).
  - `No server` — discovery failed (red).
- **Latency (optional):** updated `server.py` replies to each valid input packet with
  `PHONEPAD_ACK_V1` + sequence byte; the app shows `Connected · 12 ms`.
  An old server simply shows `—` and remains fully playable.

---

## 5. Wire protocol

Unchanged input packet (8 bytes, little-endian):

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | buttons bitmask |
| 2 | 1 | left X (-127..127) |
| 3 | 1 | left Y |
| 4 | 1 | right X |
| 5 | 1 | right Y |
| 6 | 1 | sequence |
| 7 | 1 | reserved (0) |

Discovery messages unchanged. Optional ACK:

```
ACK  = "PHONEPAD_ACK_V1" + <seq byte>   (16 bytes)
```

---

## 6. File map

| File | Change |
|---|---|
| `lib/pad_layout.dart` | **new** — `LayoutItem`, cluster IDs, defaults, load/save, reset |
| `lib/widgets/layout_toolbar.dart` | **new** — slider + Reset all + Done |
| `lib/pages/pad_page.dart` | **rewrite layout** to a position-based Stack; add edit mode; connection UI, retry, resume |
| `lib/net.dart` | persistent discovery, status/stats, optional ACK parsing |
| `lib/main.dart` | load layout before first frame (optional) |
| `lib/pages/settings_page.dart` | wording + connect feedback (manual fallback kept) |
| `server.py` | optional ACK reply |
| `README.md` | document layout editor + auto-connect |
| `pubspec.yaml` | version bump to `1.1.0+2` |

No new Flutter packages.

---

## 7. Implementation phases

1. **P0 — Backup.** Create `D:\Project of console\Consloe-v1` (source-only snapshot).
   Copy this blueprint to the project root as `SECOND_EDITION_BLUEPRINT.md` when coding starts.
2. **P1 — Layout model + Stack rendering.** Default positions, visual parity with current pad.
3. **P2 — Edit mode.** Drag, select, resize, Reset all, persistence, toolbar.
4. **P3 — Connection.** Auto-connect, retry, resume, status strip, manual fallback.
5. **P4 — Optional ACK.** Server reply + RTT display.
6. **P5 — Docs, analyze, build, manual test, commit (source files only).**

Each phase gets its own backup folder: `Consloe-v2`, `Consloe-v3`, …

---

## 8. Verification

### Automated
- `flutter analyze` → zero issues.
- `flutter build apk --debug` → success (release also works with the current debug signing).

### Manual
- Launch with server running and no saved IP → connects without typing.
- Drag every cluster; each stays inside the screen.
- Resize every cluster 70 % → 135 %; no overflow or exceptions.
- Reset all → exact default layout.
- Force-stop and reopen → saved layout restored.
- LAYOUT → Done → gameplay input works again.
- Stop server → status changes; restart server → reconnects.
- Background/foreground → reconnects.
- Old `server.py` → playable, RTT shows `—`.

### Screens
- 16:9 (2400×1080), 20:9, and 1280×720 landscape emulators.

---

## 9. Risks and limits

- Free positioning allows overlap by design; Reset all is the recovery path.
- Persistent bind on UDP 7777 can fail if another app holds it → fall back to request/response discovery.
- Router AP isolation blocks broadcasts → manual IP entry remains.
- The ACK requires the updated `server.py` for RTT; gameplay stays compatible either way.
- Layout is per phone (SharedPreferences), not synced to the PC.

---

## 10. Backup and versioning rules

- Backups live beside the project: `D:\Project of console\Consloe-vN`.
- Snapshots contain **source + config only**; exclude `build/`, `.dart_tool/`, `.venv/`,
  `__pycache__/`, `.idea/`, `.git/`, `*.apk`.
- Git commits include source files only; never stage `build/` changes.
- Never read, write, or modify `E:\Consloe`.

---

## 11. Acceptance criteria

- [ ] All seven clusters can be dragged and resized.
- [ ] Reset all restores the documented defaults.
- [ ] Layout survives app restart.
- [ ] Edit mode never sends button/axis input.
- [ ] Consloe connects with zero typing when the server is running.
- [ ] Connection recovers automatically after server restart and app resume.
- [ ] v1 protocol clients and old servers remain compatible.
- [ ] `flutter analyze` clean and APK builds.