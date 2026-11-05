import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const int dpadUp = 1 << 12;
const int dpadDown = 1 << 13;
const int dpadLeft = 1 << 14;
const int dpadRight = 1 << 15;

class DPad extends StatefulWidget {
  const DPad({super.key, required this.onChanged, this.size = 150});

  final ValueChanged<int> onChanged;
  final double size;

  @override
  State<DPad> createState() => _DPadState();
}

class _DPadState extends State<DPad> {
  final Map<int, int> _pointers = <int, int>{};
  int _mask = 0;

  void _onDown(PointerDownEvent event) {
    if (_pointers.containsKey(event.pointer)) {
      return;
    }
    _pointers[event.pointer] = 0;
    _setPointer(event.pointer, event.localPosition);
  }

  void _onMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) {
      return;
    }
    _setPointer(event.pointer, event.localPosition);
  }

  void _onEnd(PointerEvent event) {
    if (!_pointers.containsKey(event.pointer)) {
      return;
    }
    _pointers.remove(event.pointer);
    _publish();
  }

  void _setPointer(int pointer, Offset local) {
    final previous = _pointers[pointer] ?? 0;
    final next = _maskFor(local);
    _pointers[pointer] = next;

    final gained = next & ~previous;
    if (gained != 0) {
      if (previous == 0) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    }

    _publish();
  }

  void _publish() {
    var next = 0;
    for (final value in _pointers.values) {
      next |= value;
    }
    if (next == _mask) {
      return;
    }
    setState(() {
      _mask = next;
    });
    widget.onChanged(next);
  }

  int _maskFor(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final delta = local - center;
    if (delta.distance < widget.size * 0.10) {
      return 0;
    }

    final angle = math.atan2(delta.dy, delta.dx) * 180 / math.pi;
    if (angle >= -22.5 && angle < 22.5) {
      return dpadRight;
    }
    if (angle >= 22.5 && angle < 67.5) {
      return dpadRight | dpadDown;
    }
    if (angle >= 67.5 && angle < 112.5) {
      return dpadDown;
    }
    if (angle >= 112.5 && angle < 157.5) {
      return dpadDown | dpadLeft;
    }
    if (angle >= 157.5 || angle < -157.5) {
      return dpadLeft;
    }
    if (angle >= -157.5 && angle < -112.5) {
      return dpadLeft | dpadUp;
    }
    if (angle >= -112.5 && angle < -67.5) {
      return dpadUp;
    }
    return dpadUp | dpadRight;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'Directional pad',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onEnd,
        onPointerCancel: _onEnd,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _DPadPainter(mask: _mask, accent: accent),
          ),
        ),
      ),
    );
  }
}

class _DPadPainter extends CustomPainter {
  const _DPadPainter({required this.mask, required this.accent});

  final int mask;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final center = size.center(Offset.zero);
    final arm = side * 0.35;
    final radius = Radius.circular(side * 0.08);

    final horizontal = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: side, height: arm),
          radius,
        ),
      );
    final vertical = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: arm, height: side),
          radius,
        ),
      );
    final body = Path.combine(PathOperation.union, horizontal, vertical);

    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF262B33), Color(0xFF111419)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(body, fill);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, side * 0.01)
      ..color = Colors.white.withValues(alpha: 0.14);
    canvas.drawPath(body, border);

    final offset = side * 0.30;
    _drawDirection(
      canvas,
      center + Offset(0, -offset),
      0,
      mask & dpadUp != 0,
      side,
    );
    _drawDirection(
      canvas,
      center + Offset(offset, 0),
      math.pi / 2,
      mask & dpadRight != 0,
      side,
    );
    _drawDirection(
      canvas,
      center + Offset(0, offset),
      math.pi,
      mask & dpadDown != 0,
      side,
    );
    _drawDirection(
      canvas,
      center + Offset(-offset, 0),
      -math.pi / 2,
      mask & dpadLeft != 0,
      side,
    );

    canvas.drawCircle(
      center,
      side * 0.075,
      Paint()..color = const Color(0xFF0C0F13),
    );
    canvas.drawCircle(
      center,
      side * 0.075,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.10),
    );
  }

  void _drawDirection(
    Canvas canvas,
    Offset center,
    double angle,
    bool pressed,
    double side,
  ) {
    if (pressed) {
      canvas.drawCircle(
        center,
        side * 0.15,
        Paint()..color = accent.withValues(alpha: 0.16),
      );
    }

    final height = side * 0.075;
    final arrow = Path()
      ..moveTo(0, -height)
      ..lineTo(-height * 0.85, height * 0.6)
      ..lineTo(height * 0.85, height * 0.6)
      ..close();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.drawPath(
      arrow,
      Paint()..color = pressed ? accent : Colors.white.withValues(alpha: 0.38),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DPadPainter oldDelegate) {
    return mask != oldDelegate.mask || accent != oldDelegate.accent;
  }
}
