import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'net.dart';
import 'pages/pad_page.dart';
import 'pages/pair_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final prefs = await SharedPreferences.getInstance();
  final ip = prefs.getString(pairedIpKey) ?? '';
  final token = prefs.getString(pairedTokenKey) ?? '';
  final initial = ip.isEmpty || token.isEmpty
      ? null
      : PairSession(ip: ip, token: token);

  runApp(PhonePadApp(initial: initial));
}

class PhonePadApp extends StatelessWidget {
  const PhonePadApp({super.key, required this.initial});

  final PairSession? initial;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gamepad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B93FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF07090C),
      ),
      home: HomePage(initial: initial),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.initial});

  final PairSession? initial;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  PairSession? _session;
  String? _lastIp;
  String? _notice;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _session = widget.initial;
    _lastIp = widget.initial?.ip;
    if (_session != null) {
      _checking = true;
      _reconnect(_session!);
    }
  }

  Future<void> _reconnect(PairSession session) async {
    try {
      final live = await reconnectSession(session);
      if (!mounted) {
        return;
      }
      await _saveSession(live);
      if (!mounted) {
        return;
      }
      setState(() {
        _session = live;
        _lastIp = live.ip;
        _notice = null;
        _checking = false;
      });
    } on PairException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _session = null;
        _notice = error.message;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _session = null;
        _notice = 'Could not reach the saved PC. Enter its pair code again.';
        _checking = false;
      });
    }
  }

  Future<void> _saveSession(PairSession session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(pairedIpKey, session.ip);
      await prefs.setString(pairedTokenKey, session.token);
    } catch (_) {
      // The current session still works if persistence is unavailable.
    }
  }

  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(pairedIpKey);
      await prefs.remove(pairedTokenKey);
    } catch (_) {
      // Nothing else to do.
    }
  }

  Future<void> _paired(PairSession session) async {
    await _saveSession(session);
    if (!mounted) {
      return;
    }
    setState(() {
      _session = session;
      _lastIp = session.ip;
      _notice = null;
    });
  }

  Future<void> _unpair() async {
    await _clearSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _session = null;
      _notice = 'Unpaired. Enter the code shown on the PC to connect again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget home;
    if (_checking) {
      home = const _ReconnectSplash();
    } else if (_session != null) {
      final session = _session!;
      home = PadPage(
        key: ValueKey('${session.ip}-${session.token}'),
        session: session,
        onUnpair: _unpair,
      );
    } else {
      home = PairPage(
        onPaired: _paired,
        notice: _notice,
        lastIp: _lastIp,
      );
    }

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: home,
      ),
    );
  }
}

class _ReconnectSplash extends StatelessWidget {
  const _ReconnectSplash();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.0,
          colors: [Color(0xFF122033), Color(0xFF07090C)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.12),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Icon(
                  Icons.sports_esports,
                  size: 36,
                  color: accent,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'GAMEPAD',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Looking for your paired PC',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
