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

  @override
  Stream<QcState> run() async* {
    yield const QcLoading();
    try {
      if (!await _api.quickConnectEnabled()) {
        yield const QcDisabled();
        return;
      }
      while (true) {
        final session = await _api.initiateQuickConnect();
        yield QcWaiting(session.code);

        var expired = false;
        while (!expired) {
          await Future<void>.delayed(_pollInterval);
          try {
            final state = await _api.quickConnectState(session.secret);
            if (state.authenticated) {
              yield QcApproved(await _auth.completeQuickConnect(session.secret));
              return;
            }
          } on NotFoundException {
            expired = true;
          } on UnauthorizedException {
            expired = true;
          }
        }
      }
    } on ApiException catch (e) {
      yield QcError(e);
    } on Object catch (e) {
      yield QcError(e);
    }
  }
}
