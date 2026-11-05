import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const int shoulderL1 = 1 << 4;
const int shoulderR1 = 1 << 5;
const int shoulderL2 = 1 << 6;
const int shoulderR2 = 1 << 7;

class ShoulderButton extends StatefulWidget {
  const ShoulderButton({
    super.key,
    required this.label,
    required this.onChanged,
    this.width = 100,
    this.height = 42,
  });

  final String label;
  final ValueChanged<bool> onChanged;
  final double width;
  final double height;

  @override
  State<ShoulderButton> createState() => _ShoulderButtonState();
}

class _ShoulderButtonState extends State<ShoulderButton> {
  final Set<int> _pointers = <int>{};

  void _onDown(PointerDownEvent event) {
    if (!_pointers.add(event.pointer)) {
      return;
    }
    if (_pointers.length == 1) {
      HapticFeedback.lightImpact();
      widget.onChanged(true);
      setState(() {});
    }
  }

  void _onEnd(PointerEvent event) {
    if (!_pointers.remove(event.pointer)) {
      return;
    }
    if (_pointers.isEmpty) {
      widget.onChanged(false);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _pointers.isNotEmpty;
    final accent = Theme.of(context).colorScheme.primary;
    final radius = widget.height * 0.32;

    return Semantics(
      button: true,
      value: pressed ? 'pressed' : 'released',
      label: widget.label,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerUp: _onEnd,
        onPointerCancel: _onEnd,
        child: AnimatedScale(
          scale: pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 70),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: widget.width,
            height: widget.height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: pressed ? accent : Colors.white.withValues(alpha: 0.16),
                width: pressed ? 1.6 : 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: pressed
                    ? [
                        accent.withValues(alpha: 0.38),
                        accent.withValues(alpha: 0.16),
                      ]
                    : const [Color(0xFF272C34), Color(0xFF14171C)],
              ),
              boxShadow: pressed
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.32),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: pressed
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
