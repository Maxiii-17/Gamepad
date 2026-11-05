import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../keep_awake.dart';
import '../net.dart';
import '../pad_layout.dart';
import '../widgets/dpad.dart';
import '../widgets/face_buttons.dart';
import '../widgets/shoulder_button.dart';
import '../widgets/stick.dart';

const int _selectBit = 1 << 8;
const int _startBit = 1 << 9;
const int _l3Bit = 1 << 10;
const int _r3Bit = 1 << 11;
const int _psBit = 1 << 16;

const int _turboMask = 0x3F;

class PadPage extends StatefulWidget {
  const PadPage({
    super.key,
    required this.session,
    required this.onUnpair,
  });

  final PairSession session;
  final VoidCallback onUnpair;

  @override
  State<PadPage> createState() => _PadPageState();
}

class _PadPageState extends State<PadPage> with WidgetsBindingObserver {
  late final PadNet _net;
  final PadState _pad = PadState();

  bool _ready = false;
  bool _linked = false;
  bool _editMode = false;
  bool _turbo = false;
  bool _turboPhase = false;
  bool _disposing = false;
  String? _error;
  int _faceMask = 0;
  int _dpadMask = 0;
  int _auxMask = 0;
  int _controlEpoch = 0;
  Timer? _turboTimer;
  Map<String, LayoutItem> _layout = defaultPadLayout();
  String _selectedCluster = 'center';
  int? _dragPointer;
  String? _dragCluster;

  @override
  void initState() {
    super.initState();
    _net = PadNet(onLinkChanged: _onLinkChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(setKeepScreenOn(true));
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_start());
      unawaited(_loadLayout());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposing = true;
    _turboTimer?.cancel();
    unawaited(setKeepScreenOn(false));
    _net.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(setKeepScreenOn(true));
      return;
    }
    _resetControls();
  }

  Future<void> _start() async {
    try {
      await _net.start(widget.session);
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = true;
        _error = null;
      });
      _net.update(_pad);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = false;
        _error = 'Open the UDP socket failed. Pair again.';
      });
    }
  }

  Future<void> _loadLayout() async {
    final layout = await loadPadLayout();
    if (!mounted) {
      return;
    }
    setState(() {
      _layout = layout;
    });
  }

  void _onLinkChanged(bool alive) {
    if (!mounted || _disposing) {
      return;
    }
    setState(() {
      _linked = alive;
    });
  }

  void _syncButtons() {
    var mask = _faceMask | _dpadMask | _auxMask;
    if (_turbo && _turboPhase) {
      mask &= ~_turboMask;
    }
    _pad.buttons = mask & 0xFFFF;
    _pad.extra = (_auxMask >> 16) & 0xFF;
    _net.update(_pad);
  }

  void _setFace(int mask) {
    _faceMask = mask;
    _syncButtons();
  }

  void _setDpad(int mask) {
    _dpadMask = mask;
    _syncButtons();
  }

  ValueChanged<bool> _auxSetter(int bit) {
    return (pressed) {
      _auxMask = pressed ? (_auxMask | bit) : (_auxMask & ~bit);
      _syncButtons();
    };
  }

  void _setLeftStick(int x, int y) {
    _pad.lx = x;
    _pad.ly = y;
    _net.update(_pad);
  }

  void _setRightStick(int x, int y) {
    _pad.rx = x;
    _pad.ry = y;
    _net.update(_pad);
  }

  void _setTurbo(bool value) {
    if (_turbo == value) {
      return;
    }
    _turboTimer?.cancel();
    _turboTimer = null;
    _turboPhase = false;
    _turbo = value;
    if (value) {
      _turboTimer = Timer.periodic(const Duration(milliseconds: 65), (_) {
        if (!mounted) {
          return;
        }
        _turboPhase = !_turboPhase;
        _syncButtons();
      });
    }
    _syncButtons();
    setState(() {});
  }

  void _resetControls() {
    _faceMask = 0;
    _dpadMask = 0;
    _auxMask = 0;
    _turboPhase = false;
    _pad.buttons = 0;
    _pad.extra = 0;
    _pad.lx = 0;
    _pad.ly = 0;
    _pad.rx = 0;
    _pad.ry = 0;
    _net.update(_pad);
    if (!mounted) {
      return;
    }
    setState(() {
      _controlEpoch++;
    });
  }

  void _openLayout() {
    if (_editMode) {
      return;
    }
    _resetControls();
    setState(() {
      _editMode = true;
      _selectedCluster = 'center';
    });
  }

  void _finishLayout() {
    setState(() {
      _editMode = false;
      _dragPointer = null;
      _dragCluster = null;
    });
    unawaited(savePadLayout(_layout));
  }

  void _resetLayout() {
    setState(() {
      _layout = defaultPadLayout();
      _selectedCluster = 'center';
    });
    unawaited(savePadLayout(_layout));
  }

  Future<void> _unpair() async {
    if (_editMode) {
      return;
    }
    _resetControls();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Unpair this PC?'),
          content: const Text(
            'Controls will stop and you will need the PC pair code to connect '
            'again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Unpair'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    unawaited(setKeepScreenOn(false));
    _net.dispose();
    widget.onUnpair();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07090C),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final centerWidth =
                (width * 0.19).clamp(138.0, 176.0).toDouble();
             final centerHeight =
                (height * 0.62).clamp(196.0, 250.0).toDouble();
            final shoulderWidth =
                (width * 0.105).clamp(58.0, 88.0).toDouble();
            final shoulderHeight =
                (height * 0.115).clamp(32.0, 44.0).toDouble();
            final slot = (width - centerWidth - 28) / 4;
            final control = math
                .min(height * 0.44, slot * 0.94)
                .clamp(84.0, 168.0)
                .toDouble();
            final faceSize = control * 1.02;

            return Stack(
              fit: StackFit.expand,
              children: [
                const Positioned.fill(child: _Backdrop()),
                _place(
                  'shouldersLeft',
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShoulderButton(
                        key: ValueKey('l1-$_controlEpoch'),
                        label: 'L1',
                        width: shoulderWidth,
                        height: shoulderHeight,
                        onChanged: _auxSetter(shoulderL1),
                      ),
                      const SizedBox(width: 6),
                      ShoulderButton(
                        key: ValueKey('l2-$_controlEpoch'),
                        label: 'L2',
                        width: shoulderWidth,
                        height: shoulderHeight,
                        onChanged: _auxSetter(shoulderL2),
                      ),
                    ],
                  ),
                  width,
                  height,
                ),
                _place(
                  'shouldersRight',
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShoulderButton(
                        key: ValueKey('r1-$_controlEpoch'),
                        label: 'R1',
                        width: shoulderWidth,
                        height: shoulderHeight,
                        onChanged: _auxSetter(shoulderR1),
                      ),
                      const SizedBox(width: 6),
                      ShoulderButton(
                        key: ValueKey('r2-$_controlEpoch'),
                        label: 'R2',
                        width: shoulderWidth,
                        height: shoulderHeight,
                        onChanged: _auxSetter(shoulderR2),
                      ),
                    ],
                  ),
                  width,
                  height,
                ),
                _place(
                  'dpad',
                  DPad(
                    key: ValueKey('dpad-$_controlEpoch'),
                    size: control,
                    onChanged: _setDpad,
                  ),
                  width,
                  height,
                ),
                _place(
                  'leftStick',
                  Stick(
                    key: ValueKey('left-stick-$_controlEpoch'),
                    size: control,
                    label: 'Left analog stick',
                    onChanged: _setLeftStick,
                  ),
                  width,
                  height,
                ),
                _place(
                  'center',
                  _buildCenterPanel(centerWidth, centerHeight),
                  width,
                  height,
                ),
                _place(
                  'rightStick',
                  Stick(
                    key: ValueKey('right-stick-$_controlEpoch'),
                    size: control,
                    label: 'Right analog stick',
                    onChanged: _setRightStick,
                  ),
                  width,
                  height,
                ),
                _place(
                  'face',
                  FaceButtons(
                    key: ValueKey('face-$_controlEpoch'),
                    size: faceSize,
                    onChanged: _setFace,
                  ),
                  width,
                  height,
                ),
                if (_editMode) _buildLayoutToolbar(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _place(String id, Widget child, double width, double height) {
    final item = _layout[id] ?? defaultPadLayout()[id]!;
    final selected = _editMode && _selectedCluster == id;

    Widget content = child;

    if (_editMode) {
      content = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          setState(() {
            _selectedCluster = id;
            _dragPointer = event.pointer;
            _dragCluster = id;
          });
        },
        onPointerMove: (event) {
          if (event.pointer != _dragPointer || _dragCluster != id) {
            return;
          }
          setState(() {
            item.x = (item.x + event.delta.dx / width).clamp(0.04, 0.96);
            item.y = (item.y + event.delta.dy / height).clamp(0.05, 0.95);
          });
        },
        onPointerUp: _endDrag,
        onPointerCancel: _endDrag,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white.withValues(alpha: 0.16),
              width: selected ? 1.6 : 1,
            ),
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
                : Colors.transparent,
          ),
          child: AbsorbPointer(child: child),
        ),
      );
    }

    return Positioned(
      left: item.x * width,
      top: item.y * height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.scale(
          scale: item.scale,
          child: content,
        ),
      ),
    );
  }
  void _endDrag(PointerEvent event) {
    if (event.pointer != _dragPointer) {
      return;
    }
    _dragPointer = null;
    _dragCluster = null;
    unawaited(savePadLayout(_layout));
  }

  Widget _buildCenterPanel(double width, double height) {
    final accent = Theme.of(context).colorScheme.primary;
    final statusColor = _error != null
        ? const Color(0xFFFF6B6B)
        : !_ready
            ? const Color(0xFFFFC857)
            : _linked
                ? const Color(0xFF4ADE80)
                : const Color(0xFFFFA94D);
    final statusText = _error != null
        ? 'Socket error'
        : !_ready
            ? 'Connecting'
            : _linked
                ? 'Sending'
                : 'No reply';
    final smallWidth = (width - 32) / 3;

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111419),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: width - 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          Text(
            'GAMEPAD',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
              color: accent.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.7),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            widget.session.ip,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 10,
                color: Colors.white.withValues(alpha: 0.38),
              ),
              const SizedBox(width: 4),
              Text(
                'PAIRED',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: Colors.white.withValues(alpha: 0.38),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 8.5,
                height: 1.25,
                color: Color(0xFFFF9A9A),
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 29,
            child: FilledButton.icon(
              onPressed: () => _setTurbo(!_turbo),
              icon: Icon(
                Icons.bolt,
                size: 14,
                color: _turbo ? Colors.black : accent,
              ),
              label: Text(
                _turbo ? 'TURBO ON' : 'TURBO',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: _turbo ? Colors.black : null,
                ),
              ),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: _turbo ? accent : null,
                foregroundColor: _turbo ? Colors.black : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _smallButton('L3', smallWidth, _auxSetter(_l3Bit)),
              const SizedBox(width: 6),
              _smallButton('R3', smallWidth, _auxSetter(_r3Bit)),
              const SizedBox(width: 6),
              _smallButton('PS', smallWidth, _auxSetter(_psBit)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              ShoulderButton(
                key: ValueKey('select-$_controlEpoch'),
                label: 'SEL',
                width: (width - 26) / 2,
                height: 27,
                onChanged: _auxSetter(_selectBit),
              ),
              const SizedBox(width: 6),
              ShoulderButton(
                key: ValueKey('start-$_controlEpoch'),
                label: 'START',
                width: (width - 26) / 2,
                height: 27,
                onChanged: _auxSetter(_startBit),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 29,
                  child: FilledButton.tonalIcon(
                    onPressed: _openLayout,
                    icon: const Icon(Icons.dashboard_customize_outlined,
                        size: 13),
                    label: const Text(
                      'LAYOUT',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 29,
                height: 29,
                child: IconButton.filledTonal(
                  onPressed: _unpair,
                  padding: EdgeInsets.zero,
                  tooltip: 'Unpair this PC',
                  icon: const Icon(Icons.link_off, size: 14),
                ),
              ),
            ],
          ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallButton(String label, double width, ValueChanged<bool> setter) {
    return SizedBox(
      width: width,
      child: ShoulderButton(
        key: ValueKey('$label-$_controlEpoch'),
        label: label,
        width: width,
        height: 26,
        onChanged: setter,
      ),
    );
  }

  Widget _buildLayoutToolbar() {
    final item = _layout[_selectedCluster] ?? defaultPadLayout()[_selectedCluster]!;
    final accent = Theme.of(context).colorScheme.primary;

    return Positioned(
      left: 10,
      right: 10,
      bottom: 8,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
            decoration: BoxDecoration(
              color: const Color(0xF211151B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 22,
                ),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dashboard_customize, size: 16, color: accent),
                  const SizedBox(width: 6),
                  const Text(
                    'LAYOUT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 92,
                    child: Text(
                      layoutLabel(_selectedCluster),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 118,
                    child: Slider(
                      value: item.scale,
                      min: 0.70,
                      max: 1.35,
                      onChanged: (value) {
                        setState(() {
                          item.scale = value;
                        });
                      },
                      onChangeEnd: (_) {
                        unawaited(savePadLayout(_layout));
                      },
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${(item.scale * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _resetLayout,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text(
                      'Reset all',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: _finishLayout,
                    icon: const Icon(Icons.check, size: 15),
                    label: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, 0.15),
          radius: 1.15,
          colors: [Color(0xFF0C1118), Color(0xFF05070A)],
        ),
      ),
    );
  }
}
