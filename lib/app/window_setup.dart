import 'dart:async';
import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';
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

/// `true` se il rettangolo [bounds] è visibile per almeno 100x100 px su
/// almeno uno dei [displays] (posizione salvata di un monitor non più
/// collegato, es. portatile scollegato dal docking).
bool isVisibleOnAnyDisplay(Rect bounds, List<Rect> displays) {
  for (final display in displays) {
    final intersection = bounds.intersect(display);
    if (intersection.width >= 100 && intersection.height >= 100) return true;
  }
  return false;
}

Future<List<Rect>> _currentDisplayRects() async {
  final displays = await screenRetriever.getAllDisplays();
  return displays
      .map((d) => (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size))
      .toList();
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
    if (saved != null && isVisibleOnAnyDisplay(saved, await _currentDisplayRects())) {
      await windowManager.setBounds(saved);
    }
    await windowManager.show();
    await windowManager.focus();
  });
  windowManager.addListener(_BoundsSaver(prefs));
}

class _BoundsSaver with WindowListener {
  _BoundsSaver(this._prefs);

  final SharedPreferences _prefs;

  Future<void> _save() async {
    if (await windowManager.isMinimized()) return;
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
