import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` mentre una schermata del player è aperta: gli avvisi di
/// aggiornamento aspettano la fine del video.
class PlayerActiveController extends Notifier<bool> {
  /// Schermate aperte: passando all'episodio successivo, per un attimo due.
  int _open = 0;

  @override
  bool build() => false;

  void enter() {
    _open++;
    _publish();
  }

  void leave() {
    if (_open > 0) _open--;
    _publish();
  }

  /// Le schermate chiamano [enter] e [leave] in `initState`/`dispose`,
  /// mentre l'albero dei widget si sta costruendo: lo stato si aggiorna
  /// subito dopo.
  void _publish() => scheduleMicrotask(() {
        if (ref.mounted) state = _open > 0;
      });
}

final playerActiveProvider =
    NotifierProvider<PlayerActiveController, bool>(PlayerActiveController.new);
