import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String padLayoutKey = 'pad_layout_v2';
const List<String> layoutClusterIds = <String>[
  'shouldersLeft',
  'dpad',
  'leftStick',
  'center',
  'rightStick',
  'face',
  'shouldersRight',
];

const Map<String, List<double>> _defaults = <String, List<double>>{
  'shouldersLeft': <double>[0.115, 0.10, 1],
  'dpad': <double>[0.105, 0.60, 1],
  'leftStick': <double>[0.295, 0.60, 1],
  'center': <double>[0.500, 0.58, 1],
  'rightStick': <double>[0.705, 0.60, 1],
  'face': <double>[0.895, 0.60, 1],
  'shouldersRight': <double>[0.885, 0.10, 1],
};

class LayoutItem {
  LayoutItem({required this.x, required this.y, required this.scale});

  double x;
  double y;
  double scale;

  LayoutItem copy() => LayoutItem(x: x, y: y, scale: scale);

  List<double> toJson() => <double>[x, y, scale];

  static LayoutItem? fromJson(Object? value) {
    if (value is! List || value.length < 3) {
      return null;
    }
    final x = value[0];
    final y = value[1];
    final scale = value[2];
    if (x is! num || y is! num || scale is! num) {
      return null;
    }
    return LayoutItem(
      x: x.toDouble().clamp(0.04, 0.96).toDouble(),
      y: y.toDouble().clamp(0.05, 0.95).toDouble(),
      scale: scale.toDouble().clamp(0.70, 1.35).toDouble(),
    );
  }
}

Map<String, LayoutItem> defaultPadLayout() {
  return <String, LayoutItem>{
    for (final id in layoutClusterIds)
      id: LayoutItem(
        x: _defaults[id]![0],
        y: _defaults[id]![1],
        scale: _defaults[id]![2],
      ),
  };
}

String layoutLabel(String id) {
  switch (id) {
    case 'shouldersLeft':
      return 'L1 / L2';
    case 'dpad':
      return 'D-pad';
    case 'leftStick':
      return 'Left stick';
    case 'center':
      return 'Center panel';
    case 'rightStick':
      return 'Right stick';
    case 'face':
      return 'Face buttons';
    case 'shouldersRight':
      return 'R1 / R2';
  }
  return id;
}

Future<Map<String, LayoutItem>> loadPadLayout() async {
  final layout = defaultPadLayout();
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(padLayoutKey);
    if (raw == null || raw.isEmpty) {
      return layout;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return layout;
    }
    for (final id in layoutClusterIds) {
      final item = LayoutItem.fromJson(decoded[id]);
      if (item != null) {
        layout[id] = item;
      }
    }
  } catch (_) {
    return defaultPadLayout();
  }
  return layout;
}

Future<void> savePadLayout(Map<String, LayoutItem> layout) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, List<double>>{
      for (final id in layoutClusterIds)
        if (layout[id] != null) id: layout[id]!.toJson(),
    };
    await prefs.setString(padLayoutKey, jsonEncode(encoded));
  } catch (_) {
    // A layout that cannot be saved still works for this session.
  }
}
