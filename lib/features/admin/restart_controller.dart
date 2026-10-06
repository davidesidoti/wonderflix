import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/api_exception.dart';
import '../auth/session_controller.dart';
import 'admin_providers.dart';

/// A che punto è il riavvio di Jellyfin (spec J §9.2).
enum RestartPhase { idle, sending, waiting, timedOut }

/// Com'è finito un riavvio, per l'avviso della pagina.
enum RestartOutcome { back, timedOut, failed, cancelled }

/// Riavvia Jellyfin e aspetta che torni. Vive con la pagina: chiudendola,
/// l'attesa si ferma senza avvisi.
class RestartController extends Notifier<RestartPhase> {
  /// Ogni quanto si chiede a Jellyfin se è tornato.
  static const pollEvery = Duration(seconds: 3);

  /// Se in questo tempo Jellyfin non è mai sembrato giù, conta come
  /// tornato: il riavvio è stato più veloce delle domande.
  static const settleAfter = Duration(seconds: 60);

  /// Oltre, "Jellyfin non risponde ancora".
  static const giveUpAfter = Duration(minutes: 3);

  /// Cresce a ogni attesa e alla chiusura: un'attesa vecchia si ferma.
  int _wait = 0;

  @override
  RestartPhase build() {
    ref.onDispose(() => _wait++);
    return RestartPhase.idle;
  }

  /// Risposte di nginx quando Jellyfin chiude la connessione fermandosi.
  static const _gatewayStatuses = {502, 503, 504};

  /// Chiede il riavvio e aspetta il ritorno. Una richiesta persa per rete, o
  /// un 502/503/504 di nginx, conta come riavvio partito: Jellyfin può
  /// fermarsi prima di rispondere.
  Future<RestartOutcome> restart() async {
    if (state == RestartPhase.sending || state == RestartPhase.waiting) {
      return RestartOutcome.cancelled;
    }
    state = RestartPhase.sending;
    try {
      await ref.read(adminApiProvider).restart();
    } on ApiException catch (error) {
      if (!_meansStarted(error)) {
        if (!ref.mounted) return RestartOutcome.cancelled;
        if (error is ForbiddenException) {
          unawaited(ref.read(sessionControllerProvider.notifier).refreshUser());
        }
        state = RestartPhase.idle;
        return RestartOutcome.failed;
      }
    }
    if (!ref.mounted) return RestartOutcome.cancelled;
    return _waitForServer(sawDown: false);
  }

  static bool _meansStarted(ApiException error) =>
      error is ServerUnreachableException ||
      (error is ServerErrorException &&
          _gatewayStatuses.contains(error.statusCode));

  /// "Ricontrolla" dopo [RestartPhase.timedOut]: Jellyfin era già giù, la
  /// prima risposta basta.
  Future<RestartOutcome> recheck() {
    if (state != RestartPhase.timedOut) {
      return Future.value(RestartOutcome.cancelled);
    }
    return _waitForServer(sawDown: true);
  }

  Future<RestartOutcome> _waitForServer({required bool sawDown}) async {
    final wait = ++_wait;
    state = RestartPhase.waiting;
    final api = ref.read(adminApiProvider);
    final started = clock.now();
    var down = sawDown;
    while (true) {
      await Future<void>.delayed(pollEvery);
      if (wait != _wait) return RestartOutcome.cancelled;
      bool up;
      try {
        up = await api.isServerUp();
      } on Object {
        up = false;
      }
      if (wait != _wait) return RestartOutcome.cancelled;
      final elapsed = clock.now().difference(started);
      if (up && (down || elapsed >= settleAfter)) {
        state = RestartPhase.idle;
        ref.read(adminEpochProvider.notifier).bump();
        return RestartOutcome.back;
      }
      if (!up) down = true;
      if (elapsed >= giveUpAfter) {
        state = RestartPhase.timedOut;
        return RestartOutcome.timedOut;
      }
    }
  }
}

final restartControllerProvider =
    NotifierProvider.autoDispose<RestartController, RestartPhase>(
        RestartController.new);
