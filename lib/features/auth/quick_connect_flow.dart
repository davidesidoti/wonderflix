import 'dart:async';

import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/auth_api.dart';
import '../../core/jellyfin/auth_models.dart';
import 'auth_service.dart';

sealed class QcState {
  const QcState();
}

final class QcLoading extends QcState {
  const QcLoading();
}

final class QcDisabled extends QcState {
  const QcDisabled();
}

final class QcWaiting extends QcState {
  const QcWaiting(this.code);
  final String code;
}

final class QcApproved extends QcState {
  const QcApproved(this.user);
  final JellyfinUser user;
}

final class QcError extends QcState {
  const QcError(this.error);
  final Object error;
}

abstract interface class QuickConnectRunner {
  /// Stream degli stati. Termina con [QcDisabled], [QcApproved] o [QcError].
  Stream<QcState> run();
}

class QuickConnectFlow implements QuickConnectRunner {
  QuickConnectFlow({
    required AuthApi api,
    required AuthService auth,
    Duration pollInterval = const Duration(seconds: 3),
  })  : _api = api,
        _auth = auth,
        _pollInterval = pollInterval;

  final AuthApi _api;
  final AuthService _auth;
  final Duration _pollInterval;

  /// Chi smette di ascoltare ("Annulla", un'altra scheda, la schermata che
  /// si chiude) ferma tutto: niente più controlli, codici nuovi o accessi.
  /// Userebbero le credenziali del profilo aperto dopo, e un loro 401 lo
  /// segnerebbe scaduto.
  @override
  Stream<QcState> run() {
    var cancelled = false;
    late final StreamController<QcState> states;
    states = StreamController<QcState>(
      onListen: () => unawaited(_run(states, () => cancelled)),
      onCancel: () {
        cancelled = true;
      },
    );
    return states.stream;
  }

  /// Non lancia mai: un errore diventa [QcError]. Prima di ogni attesa e di
  /// ogni richiesta guarda [cancelled].
  Future<void> _run(
      StreamController<QcState> states, bool Function() cancelled) async {
    void emit(QcState state) {
      if (!cancelled()) states.add(state);
    }

    try {
      emit(const QcLoading());
      if (!await _api.quickConnectEnabled()) {
        emit(const QcDisabled());
        return;
      }
      while (!cancelled()) {
        final QuickConnectState session;
        try {
          session = await _api.initiateQuickConnect();
        } on UnauthorizedException {
          // Il server ha Quick Connect disattivato (può cambiare tra la
          // verifica iniziale e questa chiamata).
          emit(const QcDisabled());
          return;
        }
        emit(QcWaiting(session.code));

        var expired = false;
        while (!expired) {
          await Future<void>.delayed(_pollInterval);
          if (cancelled()) return;
          try {
            final state = await _api.quickConnectState(session.secret);
            if (cancelled()) return;
            if (state.authenticated) {
              emit(const QcLoading());
              final user = await _auth.completeQuickConnect(session.secret);
              emit(QcApproved(user));
              return;
            }
          } on NotFoundException {
            expired = true;
          } on UnauthorizedException {
            expired = true;
          }
        }
      }
    } on Object catch (e) {
      emit(QcError(e));
    } finally {
      unawaited(states.close());
    }
  }
}
