import 'package:flutter/services.dart';

const MethodChannel _systemChannel = MethodChannel('gamepad/system');

Future<void> setKeepScreenOn(bool enabled) async {
  try {
    await _systemChannel.invokeMethod<void>('keepScreenOn', enabled);
  } on MissingPluginException {
    // The channel is Android-only; other test hosts simply ignore it.
  } on PlatformException {
    // Keeping the screen on is a convenience, never a hard requirement.
  }
}
