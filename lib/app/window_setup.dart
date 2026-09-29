import 'dart:async';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const _boundsKey = 'window_bounds';
const minWindowSize = Size(1024, 640);

String encodeBounds(Rect r) => '${r.left},${r.top},${r.width},${r.height}';

Rect? parseBounds(String? value) {
  final parts = value?.split(',').map(double.tryParse).toList();
  if (parts == null || parts.length != 4 || parts.contains(null)) return null;
  final rect = Rect.fromLTWH(parts[0]!, parts[1]!, parts[2]!, parts[3]!);
  if (rect.width < minWindowSize.width || rect.height < minWindowSize.height) {
    return null;
  }
  return rect;
}

/// Titolo, dimensione minima, posizione ricordata. La finestra viene mostrata
/// solo quando è pronta (niente lampo bianco all'avvio).
Future<void> setupWindow(SharedPreferences prefs) async {
  await windowManager.ensureInitialized();
  final saved = parseBounds(prefs.getString(_boundsKey));
  const options = WindowOptions(
    title: 'WonderFlix',
    size: Size(1440, 900),
    minimumSize: minWindowSize,
    center: true,
    backgroundColor: Color(0xFF0A0A0A),
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (saved != null) await windowManager.setBounds(saved);
    await windowManager.show();
    await windowManager.focus();
  });
  windowManager.addListener(_BoundsSaver(prefs));
}

class _BoundsSaver with WindowListener {
  _BoundsSaver(this._prefs);

  final SharedPreferences _prefs;

  Future<void> _save() async {
    if (await windowManager.isMaximized() || await windowManager.isFullScreen()) {
      return;
    }
    await _prefs.setString(_boundsKey, encodeBounds(await windowManager.getBounds()));
  }

  @override
  void onWindowResized() => unawaited(_save());

  @override
  void onWindowMoved() => unawaited(_save());
}
