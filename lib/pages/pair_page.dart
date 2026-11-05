import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net.dart';

class PairPage extends StatefulWidget {
  const PairPage({
    super.key,
    required this.onPaired,
    this.notice,
    this.lastIp,
  });

  final ValueChanged<PairSession> onPaired;
  final String? notice;
  final String? lastIp;

  @override
  State<PairPage> createState() => _PairPageState();
}

class _PairPageState extends State<PairPage> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) {
      return;
    }

    final code = _controller.text.trim();
    if (code.length != 6) {
      setState(() {
        _error = 'Enter all six digits.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    var paired = false;
    try {
      final session = await pairWithCode(code, lastIp: widget.lastIp);
      if (!mounted) {
        return;
      }
      paired = true;
      FocusScope.of(context).unfocus();
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!mounted) {
        return;
      }
      widget.onPaired(session);
    } on PairException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Pairing failed. Try again.';
      });
    } finally {
      if (mounted && !paired) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF07090C),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.55),
            radius: 1.05,
            colors: [Color(0xFF122033), Color(0xFF07090C)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF11151B).withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 40,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent.withValues(alpha: 0.34),
                              accent.withValues(alpha: 0.08),
                            ],
                          ),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Icon(
                          Icons.sports_esports,
                          size: 46,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Gamepad',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                      ),
                                ),

                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Enter the pair code shown on your PC.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.62),
                              ),
                            ),
                            if (widget.notice != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                widget.notice!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: Color(0xFFFFC857),
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 52,
                                    child: TextField(
                                      controller: _controller,
                                      enabled: !_busy,
                                      autofocus: false,
                                      textAlign: TextAlign.center,
                                      keyboardType: TextInputType.number,
                                      textInputAction: TextInputAction.done,
                                      maxLength: 6,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(6),
                                      ],
                                      onChanged: (_) {
                                        if (_error != null) {
                                          setState(() {
                                            _error = null;
                                          });
                                        }
                                      },
                                      onSubmitted: (_) => _connect(),
                                      style: const TextStyle(
                                        fontSize: 27,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 8,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                      decoration: InputDecoration(
                                        counterText: '',
                                        hintText: '000000',
                                        hintStyle: TextStyle(
                                          fontSize: 27,
                                          letterSpacing: 8,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white.withValues(
                                            alpha: 0.18,
                                          ),
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xFF090C10),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          borderSide: BorderSide(
                                            color: Colors.white.withValues(
                                              alpha: 0.12,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          borderSide: BorderSide(
                                            color: accent,
                                            width: 1.6,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  height: 52,
                                  child: FilledButton.icon(
                                    onPressed: _busy ? null : _connect,
                                    icon: _busy
                                        ? const SizedBox(
                                            width: 17,
                                            height: 17,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.link, size: 19),
                                    label: Text(_busy ? 'Pairing' : 'Pair'),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 7),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFFF9A9A),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(
                                  Icons.desktop_windows_outlined,
                                  size: 15,
                                  color: Colors.white.withValues(alpha: 0.38),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    'Start start-server.bat on the PC. The '
                                    'server window shows a six-digit code.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.48,
                                      ),
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
