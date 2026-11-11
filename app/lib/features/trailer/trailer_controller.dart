import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/trailers/trailers_api.dart';

/// A che punto è il trailer: si prepara, è pronto da [url], non c'è.
sealed class TrailerPhase {
  const TrailerPhase();
}

class TrailerPreparing extends TrailerPhase {
  const TrailerPreparing();
}

class TrailerReady extends TrailerPhase {
  const TrailerReady(this.url);

  final String url;
}

class TrailerUnavailable extends TrailerPhase {
  const TrailerUnavailable();
}

/// Chiede al plugin il trailer e, finché lo scarica, ne controlla lo stato
/// ogni [pollInterval]; dopo [maxWait] rinuncia.
class TrailerController extends ValueNotifier<TrailerPhase> {
  TrailerController(this._api, this._subject) : super(const TrailerPreparing());

  static const pollInterval = Duration(seconds: 1);
  static const maxWait = Duration(minutes: 3);

  final TrailersApi _api;
  final TrailerSubject _subject;
  Timer? _poll;
  Timer? _deadline;
  bool _disposed = false;

  void start() {
    _deadline = Timer(maxWait, () => _finish(const TrailerUnavailable()));
    unawaited(_check(() => _api.start(_subject)));
  }

  Future<void> _check(Future<TrailerStatus> Function() request) async {
    TrailerStatus status;
    try {
      status = await request();
    } on TrailerUnavailableException {
      _finish(const TrailerUnavailable());
      return;
    }
    if (_disposed || value is! TrailerPreparing) return;
    final key = status.key;
    switch (status.state) {
      case TrailerState.ready when key != null:
        _finish(TrailerReady(_api.streamUrl(key)));
      case TrailerState.downloading when key != null:
        // Un controllo alla volta: il prossimo parte quando questo risponde.
        _poll = Timer(pollInterval, () => _check(() => _api.status(key)));
      default:
        _finish(const TrailerUnavailable());
    }
  }

  void _finish(TrailerPhase phase) {
    if (_disposed || value is! TrailerPreparing) return;
    _poll?.cancel();
    _deadline?.cancel();
    value = phase;
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _deadline?.cancel();
    super.dispose();
  }
}
