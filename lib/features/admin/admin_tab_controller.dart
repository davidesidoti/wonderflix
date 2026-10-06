import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/api_exception.dart';
import '../auth/session_controller.dart';
import 'admin_poller.dart';
import 'admin_providers.dart';

/// I dati di una scheda (spec J §10): il valore dell'ultima lettura
/// riuscita, l'errore dell'ultima lettura (se è fallita) e l'ora dell'ultima
/// lettura riuscita.
class AdminData<T> {
  const AdminData({this.value, this.error, this.updatedAt});

  final T? value;
  final Object? error;
  final DateTime? updatedAt;

  /// L'ultima lettura è fallita ma restano i dati di prima: la scheda
  /// mostra "Dati non aggiornati".
  bool get stale => value != null && error != null;
}

/// Base dei controller della pagina Amministrazione (spec J §10): legge con
/// [fetch] subito e ogni [interval] mentre la finestra è in vista e la
/// pagina è visibile, e di nuovo quando Jellyfin torna da un riavvio. Un 403
/// fa rileggere l'utente: se non è più admin, la pagina va via (§12).
abstract class AdminTabController<T> extends Notifier<AdminData<T>> {
  late AdminPoller _poller;

  /// Ogni quanto si rilegge.
  Duration get interval;

  /// Una lettura. Gli errori sono di solito [ApiException].
  Future<T> fetch();

  @override
  AdminData<T> build() {
    final poller = AdminPoller(read: _read, interval: interval);
    _poller = poller;
    ref.onDispose(poller.dispose);

    // Si rilegge solo con la finestra in vista e la pagina visibile. Quando
    // un'altra pagina la copre (un titolo, il player), Riverpod mette in
    // pausa l'ascolto: il provider riceve `onCancel`, e `onResume` quando
    // torna in vista.
    var listened = true;
    var windowVisible = true;
    void sync() {
      if (listened && windowVisible) {
        poller.start();
      } else {
        poller.stop();
      }
    }

    ref.onCancel(() {
      listened = false;
      sync();
    });
    ref.onResume(() {
      listened = true;
      sync();
    });
    ref.listen<bool>(adminForegroundProvider, (_, visible) {
      windowVisible = visible;
      sync();
    }, fireImmediately: true);
    ref.listen<int>(adminEpochProvider, (_, _) => unawaited(poller.now()));
    return AdminData<T>();
  }

  /// Rilegge subito ("Riprova", dopo un'azione).
  Future<void> refresh() => _poller.now();

  /// Cambia il ritmo della rilettura (Manutenzione, spec J §9.4).
  void setInterval(Duration value) => _poller.interval = value;

  Future<void> _read() async {
    try {
      final value = await fetch();
      if (!ref.mounted) return;
      state = AdminData<T>(value: value, updatedAt: clock.now());
    } on Object catch (error) {
      if (!ref.mounted) return;
      if (error is ForbiddenException) {
        unawaited(ref.read(sessionControllerProvider.notifier).refreshUser());
      }
      state = AdminData<T>(
          value: state.value, error: error, updatedAt: state.updatedAt);
    }
  }
}
