import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Stick extends StatefulWidget {
  const Stick({
    super.key,
    required this.onChanged,
    this.size = 150,
    this.deadZone = 0.12,
    this.label = 'Analog stick',
  })  : assert(size > 0, 'size must be positive'),
        assert(deadZone >= 0 && deadZone < 1, 'deadZone must be in [0, 1)');

  final void Function(int x, int y) onChanged;
  final double size;
  final double deadZone;
  final String label;

  @override
  State<Stick> createState() => _StickState();
}

class _StickState extends State<Stick> {
  int? _pointer;
  Offset _knob = Offset.zero;
  bool _active = false;

  void _onDown(PointerDownEvent event) {
    if (_pointer != null) {
      return;
    }
    _pointer = event.pointer;
    _active = true;
    HapticFeedback.lightImpact();
    _update(event.localPosition);
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _update(event.localPosition);
  }

  void _onEnd(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    setState(() {
      _active = false;
      _knob = Offset.zero;
    });
    widget.onChanged(0, 0);
  }

  void _update(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final travel = widget.size * 0.28;
    final delta = local - center;
    final distance = delta.distance;
    final clamped = distance > travel ? delta / distance * travel : delta;

    final magnitude = math.min(1.0, clamped.distance / travel);
    double x = 0;
    double y = 0;

    if (magnitude > widget.deadZone) {
      final scaled = (magnitude - widget.deadZone) / (1 - widget.deadZone);
      final unit = clamped / clamped.distance;
      x = unit.dx * scaled;
      y = unit.dy * scaled;
    }

    setState(() {
      _active = true;
      _knob = clamped;
    });
    widget.onChanged((x * 127).round(), (-y * 127).round());
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: widget.label,
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
            painter: _StickPainter(
              knob: _knob,
              accent: accent,
              active: _active,
            ),
          ),
        ),
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  const _StickPainter({
    required this.knob,
    required this.accent,
    required this.active,
  });

  final Offset knob;
  final Color accent;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final center = size.center(Offset.zero);
    final baseRadius = side / 2;
    final knobRadius = side * 0.20;
    final baseRect = Rect.fromCircle(center: center, radius: baseRadius);

    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF22262E), Color(0xFF0A0C0F)],
      ).createShader(baseRect);
    canvas.drawCircle(center, baseRadius, basePaint);

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.012
      ..color = Colors.white.withValues(alpha: 0.14);
    canvas.drawCircle(
      center,
      baseRadius - rimPaint.strokeWidth / 2,
      rimPaint,
    );

    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.06);
    canvas.drawCircle(center, side * 0.32, guidePaint);
    canvas.drawCircle(center, side * 0.16, guidePaint);

    final knobCenter = center + knob;
    canvas.drawCircle(
      knobCenter + Offset(0, side * 0.015),
      knobRadius,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );

    final knobRect = Rect.fromCircle(center: knobCenter, radius: knobRadius);
    final knobPaint = Paint()
      ..shader = RadialGradient(
        colors: active
            ? [accent.withValues(alpha: 0.95), accent.withValues(alpha: 0.55)]
            : const [Color(0xFF3D434E), Color(0xFF1A1E24)],
      ).createShader(knobRect);
    canvas.drawCircle(knobCenter, knobRadius, knobPaint);

    final knobRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.012
      ..color = active
          ? accent.withValues(alpha: 0.9)
          : Colors.white.withValues(alpha: 0.20);
    canvas.drawCircle(
      knobCenter,
      knobRadius - knobRim.strokeWidth / 2,
      knobRim,
    );

    canvas.drawCircle(
      knobCenter,
      knobRadius * 0.28,
      Paint()..color = Colors.white.withValues(alpha: active ? 0.32 : 0.10),
    );
  }

  @override
  bool shouldRepaint(_StickPainter oldDelegate) {
    return knob != oldDelegate.knob ||
        accent != oldDelegate.accent ||
        active != oldDelegate.active;
  }
}
