import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int padPort = 7777;
const String pairedIpKey = 'paired_ip_v2';
const String pairedTokenKey = 'paired_token_v2';
const String discoveryRequest = 'PHONEPAD_DISCOVER_V1';
const String discoveryAnnounce = 'PHONEPAD_SERVER_V1';
const String pairRequestPrefix = 'GAMEPAD_PAIR ';
const String helloPrefix = 'GAMEPAD_HELLO ';
const String pairedPrefix = 'GAMEPAD_PAIRED ';
const String readyReply = 'GAMEPAD_READY';
const String badCodeReply = 'GAMEPAD_BAD_CODE';
const String ackReply = 'GAMEPAD_ACK';

final RegExp _tokenPattern = RegExp(r'^[0-9a-f]{16}$');
final RegExp _nonDigit = RegExp(r'\D');

class PairSession {
  const PairSession({required this.ip, required this.token});

  final String ip;
  final String token;
}

class PairException implements Exception {
  const PairException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<String?>? _activeDiscovery;

Future<String?> discoverServer({
  Duration timeout = const Duration(seconds: 4),
}) {
  final active = _activeDiscovery;
  if (active != null) {
    return active;
  }

  final future = _runDiscovery(timeout);
  _activeDiscovery = future;
  future.whenComplete(() {
    if (identical(_activeDiscovery, future)) {
      _activeDiscovery = null;
    }
  });
  return future;
}

Future<String?> _runDiscovery(Duration timeout) async {
  RawDatagramSocket? socket;
  StreamSubscription<RawSocketEvent>? subscription;

  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, padPort);
    socket.broadcastEnabled = true;

    final found = Completer<String?>();
    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read || found.isCompleted) {
        return;
      }
      final datagram = socket?.receive();
      if (datagram == null) {
        return;
      }
      final message = utf8.decode(datagram.data, allowMalformed: true);
      if (message == discoveryAnnounce) {
        found.complete(datagram.address.address);
      }
    });

    try {
      socket.send(
        utf8.encode(discoveryRequest),
        InternetAddress('255.255.255.255'),
        padPort,
      );
    } on SocketException {
      // Announcements still arrive if the probe broadcast is dropped.
    }

    return await found.future.timeout(timeout, onTimeout: () => null);
  } on SocketException {
    return null;
  } finally {
    await subscription?.cancel();
    socket?.close();
  }
}

Future<List<InternetAddress>> _localBroadcastTargets() async {
  final targets = <String>{};
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        final parts = address.address.split('.');
        if (parts.length != 4) {
          continue;
        }
        // 192.0.0.0/24 and 169.254.0.0/16 are carrier and link-local paths,
        // not the PC hotspot subnet.
        if (address.address.startsWith('192.0.0.') ||
            address.address.startsWith('169.254.')) {
          continue;
        }
        targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
    }
  } catch (_) {
    // The server's announcement is still the primary discovery path.
  }
  return targets.map(InternetAddress.new).toList(growable: false);
}

/// Pairs with the PC using the six-digit code shown in its server window.
Future<PairSession> pairWithCode(String code, {String? lastIp}) async {  final digits = code.replaceAll(_nonDigit, '');
  if (digits.length != 6) {
    throw const PairException('Enter the 6-digit code from the PC.');
  }

  RawDatagramSocket? socket;
  StreamSubscription<RawSocketEvent>? subscription;
  Timer? retry;

  try {
    // Binding 7777 lets us hear the server's LAN announcement, which gives us
    // the PC's address even when Android routes 255.255.255.255 to cellular.
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, padPort);
    } on SocketException {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }
    socket.broadcastEnabled = true;
    final request = utf8.encode('$pairRequestPrefix$digits');
    final found = Completer<PairSession>();
    final known = <String>{};
    final subnets = await _localBroadcastTargets();

    void sendTo(InternetAddress target) {
      try {
        socket?.send(request, target, padPort);
      } on SocketException {
        // Other targets and retries may still work.
      }
    }

    void send() {
      final targets = <String>{};
      if (lastIp != null && lastIp.trim().isNotEmpty) {
        targets.add(lastIp.trim());
      }
      targets.addAll(known);
      for (final ip in targets) {
        final target = InternetAddress.tryParse(ip);
        if (target != null && target.type == InternetAddressType.IPv4) {
          sendTo(target);
        }
      }
      for (final target in subnets) {
        sendTo(target);
      }
      sendTo(InternetAddress('255.255.255.255'));
    }

    subscription = socket.listen(
      (event) {
        if (event != RawSocketEvent.read || found.isCompleted) {
          return;
        }
        final datagram = socket?.receive();
        if (datagram == null) {
          return;
        }
        final message = utf8.decode(datagram.data, allowMalformed: true);
        if (message == discoveryAnnounce) {
          final ip = datagram.address.address;
          if (known.add(ip)) {
            sendTo(datagram.address);
          }
          return;
        }
        if (message == badCodeReply) {
          found.completeError(
            const PairException('Wrong code. Check the PC server window.'),
          );
          return;
        }
        if (!message.startsWith(pairedPrefix)) {
          return;
        }
        final token =
            message.substring(pairedPrefix.length).trim().toLowerCase();
        if (!_tokenPattern.hasMatch(token)) {
          return;
        }
        found.complete(
          PairSession(ip: datagram.address.address, token: token),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!found.isCompleted) {
          found.completeError(
            const PairException('Network error while pairing.'),
          );
        }
      },
    );

    send();
    retry = Timer.periodic(const Duration(milliseconds: 600), (_) => send());

    try {
      return await found.future.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      throw const PairException(
        'No PC answered. Check the code and that the server is open.',
      );
    }
  } on SocketException {
    throw const PairException(
      'Network unavailable. Join the PC hotspot or Wi-Fi first.',
    );
  } finally {
    retry?.cancel();
    await subscription?.cancel();
    socket?.close();
  }
}

/// Tries the saved address, then discovery, without asking for the code again.
Future<PairSession> reconnectSession(PairSession session) async {
  final direct = await _hello(session, session.ip);
  if (direct != null) {
    return direct;
  }

  final found = await discoverServer(timeout: const Duration(seconds: 3));
  if (found != null && found != session.ip) {
    final retry = await _hello(session, found);
    if (retry != null) {
      return retry;
    }
  }

  throw const PairException(
    'Could not reach the saved PC. Enter its pair code again.',
  );
}

Future<PairSession?> _hello(PairSession session, String ip) async {
  final target = InternetAddress.tryParse(ip.trim());
  if (target == null || target.type != InternetAddressType.IPv4) {
    return null;
  }

  RawDatagramSocket? socket;
  StreamSubscription<RawSocketEvent>? subscription;
  Timer? retry;

  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final found = Completer<PairSession>();
    final request = utf8.encode('$helloPrefix${session.token}');

    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read || found.isCompleted) {
        return;
      }
      final datagram = socket?.receive();
      if (datagram == null) {
        return;
      }
      final message = utf8.decode(datagram.data, allowMalformed: true);
      if (message == readyReply) {
        found.complete(
          PairSession(ip: datagram.address.address, token: session.token),
        );
      }
    });

    void send() {
      try {
        socket?.send(request, target, padPort);
      } on SocketException {
        // Retried once more below.
      }
    }

    send();
    retry = Timer.periodic(const Duration(milliseconds: 450), (_) => send());

    try {
      return await found.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      return null;
    }
  } on SocketException {
    return null;
  } finally {
    retry?.cancel();
    await subscription?.cancel();
    socket?.close();
  }
}

class PadState {
  int buttons = 0;
  int extra = 0;
  int lx = 0;
  int ly = 0;
  int rx = 0;
  int ry = 0;
}

class PadNet {
  PadNet({this.onLinkChanged});

  final void Function(bool alive)? onLinkChanged;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  InternetAddress? _target;
  Timer? _heartbeat;
  Timer? _ackWatch;
  PadState _state = PadState();
  PadState? _lastSent;
  Uint8List? _tokenBytes;
  DateTime _lastAck = DateTime.fromMillisecondsSinceEpoch(0);
  int _seq = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _linked = false;

  bool get linked => _linked;

  Future<void> start(PairSession session) async {
    if (_disposed) {
      throw StateError('PadNet has been disposed');
    }

    final target = InternetAddress.tryParse(session.ip.trim());
    if (target == null || target.type != InternetAddressType.IPv4) {
      throw ArgumentError.value(session.ip, 'ip', 'Enter a valid IPv4 address');
    }
    final tokenBytes = _parseToken(session.token);

    _stopSocket();
    final generation = _generation;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

    if (_disposed || generation != _generation) {
      socket.close();
      return;
    }

    _target = target;
    _socket = socket;
    _tokenBytes = tokenBytes;
    _lastSent = null;
    _lastAck = DateTime.now();
    _setLinked(true);
    _subscription = socket.listen(
      _onSocketEvent,
      onError: (Object error, StackTrace stackTrace) {
        _setLinked(false);
      },
    );
    _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) => _send());
    _ackWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (DateTime.now().difference(_lastAck) >
          const Duration(milliseconds: 3500)) {
        _setLinked(false);
      }
    });
  }

  void update(PadState state) {
    _state = _copy(state);
    if (_disposed || _socket == null) {
      return;
    }

    final last = _lastSent;
    if (last == null || !_same(last, _state)) {
      _send();
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _setLinked(false);
    _stopSocket();
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }
    final datagram = _socket?.receive();
    if (datagram == null) {
      return;
    }
    final message = utf8.decode(datagram.data, allowMalformed: true);
    if (message == ackReply) {
      _lastAck = DateTime.now();
      _setLinked(true);
    }
  }

  void _setLinked(bool value) {
    if (_linked == value) {
      return;
    }
    _linked = value;
    onLinkChanged?.call(value);
  }

  void _stopSocket() {
    _generation++;
    _heartbeat?.cancel();
    _heartbeat = null;
    _ackWatch?.cancel();
    _ackWatch = null;
    _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
    _target = null;
    _tokenBytes = null;
    _lastSent = null;
  }

  void _send() {
    final socket = _socket;
    final target = _target;
    final tokenBytes = _tokenBytes;
    if (_disposed ||
        socket == null ||
        target == null ||
        tokenBytes == null) {
      return;
    }

    final state = _state;
    final data = ByteData(16)
      ..setUint16(0, state.buttons & 0xFFFF, Endian.little)
      ..setInt8(2, _axis(state.lx))
      ..setInt8(3, _axis(state.ly))
      ..setInt8(4, _axis(state.rx))
      ..setInt8(5, _axis(state.ry))
      ..setUint8(6, _seq)
      ..setUint8(7, state.extra & 0xFF);
    for (var i = 0; i < tokenBytes.length; i++) {
      data.setUint8(8 + i, tokenBytes[i]);
    }

    _seq = (_seq + 1) & 0xFF;

    try {
      socket.send(data.buffer.asUint8List(), target, padPort);
      _lastSent = _copy(state);
    } on SocketException {
      _lastSent = null;
      _setLinked(false);
    }
  }
}

Uint8List _parseToken(String token) {
  final value = token.trim().toLowerCase();
  if (!_tokenPattern.hasMatch(value)) {
    throw ArgumentError.value(token, 'token', 'Invalid pairing token');
  }
  final bytes = Uint8List(8);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(value.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

int _axis(int value) {
  if (value < -127) {
    return -127;
  }
  if (value > 127) {
    return 127;
  }
  return value;
}

PadState _copy(PadState state) {
  return PadState()
    ..buttons = state.buttons
    ..extra = state.extra
    ..lx = state.lx
    ..ly = state.ly
    ..rx = state.rx
    ..ry = state.ry;
}

bool _same(PadState a, PadState b) {
  return a.buttons == b.buttons &&
      a.extra == b.extra &&
      a.lx == b.lx &&
      a.ly == b.ly &&
      a.rx == b.rx &&
      a.ry == b.ry;
}
