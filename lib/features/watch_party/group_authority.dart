import 'package:logging/logging.dart';

import '../../core/syncplay/syncplay_api.dart';
import '../../core/video/video_engine.dart';
import '../player/playback_authority.dart';

final _log = Logger('watchparty');

/// Nel watch party pausa, ripresa e salti dell'utente diventano richieste al
/// gruppo (spec B §6.1). Il motore si muove con i comandi del gruppo, tranne
/// la pausa e il salto, che si vedono subito.
class GroupAuthority implements PlaybackAuthority {
  GroupAuthority({required SyncPlayApi api, required VideoEngine engine})
      : _api = api,
        _engine = engine;

  final SyncPlayApi _api;
  final VideoEngine _engine;

  /// Con il gruppo in attesa fa ripartire tutti senza aspettare.
  @override
  Future<void> play() => _send('ripresa', _api.unpause);

  @override
  Future<void> pause() async {
    await _engine.pause();
    await _send('pausa', _api.pause);
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _engine.pause();
    await _engine.seek(position);
    await _send('salto', () => _api.seek(position));
  }

  Future<void> _send(String what, Future<void> Function() request) async {
    try {
      await request();
    } on Object catch (error) {
      _log.warning('$what non inviata al gruppo: $error');
    }
  }
}
