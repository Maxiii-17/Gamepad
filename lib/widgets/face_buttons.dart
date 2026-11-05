import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const int faceCross = 1 << 0;
const int faceCircle = 1 << 1;
const int faceSquare = 1 << 2;
const int faceTriangle = 1 << 3;

const Color _crossColor = Color(0xFF5B93FF);
const Color _circleColor = Color(0xFFFF6B6B);
const Color _squareColor = Color(0xFFFF7AC8);
const Color _triangleColor = Color(0xFF57D9A3);

class FaceButtons extends StatefulWidget {
  const FaceButtons({super.key, required this.onChanged, this.size = 170});

  final ValueChanged<int> onChanged;
  final double size;

  @override
  State<FaceButtons> createState() => _FaceButtonsState();
}

class _FaceButtonsState extends State<FaceButtons> {
  final Map<int, int> _pointers = <int, int>{};
  int _mask = 0;

  void _onDown(PointerDownEvent event) {
    if (_pointers.containsKey(event.pointer)) {
      return;
    }
    final bit = _hitTest(event.localPosition);
    if (bit == 0) {
      return;
    }
    _pointers[event.pointer] = bit;
    HapticFeedback.lightImpact();
    _publish();
  }

  void _onEnd(PointerEvent event) {
    if (_pointers.remove(event.pointer) == null) {
      return;
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

  int _hitTest(Offset local) {
    final size = Size(widget.size, widget.size);
    final radius = widget.size * 0.19;
    var bestBit = 0;
    var bestDistance = double.infinity;

    for (final bit in const [
      faceCross,
      faceCircle,
      faceSquare,
      faceTriangle,
    ]) {
      final center = _centerFor(bit, size);
      final distance = (local - center).distance;
      if (distance <= radius && distance < bestDistance) {
        bestBit = bit;
        bestDistance = distance;
      }
    }
    return bestBit;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Face buttons',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerUp: _onEnd,
        onPointerCancel: _onEnd,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(painter: _FaceButtonsPainter(mask: _mask)),
        ),
      ),
    );
  }
}

Offset _centerFor(int bit, Size size) {
  final center = size.center(Offset.zero);
  final distance = size.shortestSide * 0.30;
  if (bit == faceTriangle) {
    return center + Offset(0, -distance);
  }
  if (bit == faceCircle) {
    return center + Offset(distance, 0);
  }
  if (bit == faceCross) {
    return center + Offset(0, distance);
  }
  return center + Offset(-distance, 0);
}

Color _colorFor(int bit) {
  if (bit == faceTriangle) {
    return _triangleColor;
  }
  if (bit == faceCircle) {
    return _circleColor;
  }
  if (bit == faceCross) {
    return _crossColor;
  }
  return _squareColor;
}

class _FaceButtonsPainter extends CustomPainter {
  const _FaceButtonsPainter({required this.mask});

  final int mask;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide * 0.17;
    for (final bit in const [
      faceCross,
      faceCircle,
      faceSquare,
      faceTriangle,
    ]) {
      _drawButton(canvas, size, bit, radius);
    }
  }

  void _drawButton(Canvas canvas, Size size, int bit, double radius) {
    final center = _centerFor(bit, size);
    final color = _colorFor(bit);
    final pressed = mask & bit != 0;

    canvas.drawCircle(
      center + Offset(0, radius * 0.10),
      radius,
      Paint()..color = Colors.black.withValues(alpha: 0.40),
    );

    if (pressed) {
      canvas.drawCircle(
        center,
        radius * 1.16,
        Paint()..color = color.withValues(alpha: 0.18),
      );
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color =
            pressed ? color.withValues(alpha: 0.28) : const Color(0xFF171A20),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, radius * 0.09)
        ..color = pressed ? color : color.withValues(alpha: 0.80),
    );

    _drawGlyph(canvas, center, radius * 0.52, bit, color, pressed);
  }

  void _drawGlyph(
    Canvas canvas,
    Offset center,
    double size,
    int bit,
    Color color,
    bool pressed,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, size * 0.16)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = pressed ? Colors.white : color;

    if (bit == faceCross) {
      final d = size * 0.72;
      canvas.drawLine(
        center + Offset(-d, -d),
        center + Offset(d, d),
        paint,
      );
      canvas.drawLine(
        center + Offset(d, -d),
        center + Offset(-d, d),
        paint,
      );
      return;
    }

    if (bit == faceCircle) {
      canvas.drawCircle(center, size * 0.82, paint);
      return;
    }

    if (bit == faceSquare) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center,
            width: size * 1.45,
            height: size * 1.45,
          ),
          Radius.circular(size * 0.18),
        ),
        paint,
      );
      return;
    }

    final triangle = Path()
      ..moveTo(center.dx, center.dy - size * 0.92)
      ..lineTo(center.dx - size * 0.90, center.dy + size * 0.62)
      ..lineTo(center.dx + size * 0.90, center.dy + size * 0.62)
      ..close();
    canvas.drawPath(triangle, paint);
  }

  @override
  bool shouldRepaint(_FaceButtonsPainter oldDelegate) {
    return mask != oldDelegate.mask;
  }
}
