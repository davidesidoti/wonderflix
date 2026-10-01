import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../watch_party/party_notices.dart';
import 'segments.dart';

/// Riscontro di un tasto nella pillola del player (spec D §9.2).
@immutable
sealed class PlayerFeedback {
  const PlayerFeedback();
}

/// Spazio: [playing] è lo stato dopo il tasto.
final class PlayFeedback extends PlayerFeedback {
  const PlayFeedback({required this.playing});

  final bool playing;
}

/// ←/→: [offset] è la somma dei salti di fila, [target] la posizione di
/// arrivo.
final class SeekFeedback extends PlayerFeedback {
  const SeekFeedback({required this.offset, required this.target});

  final Duration offset;
  final Duration target;
}

/// ↑/↓ e M: volume (0–100) e muto dopo il tasto.
final class VolumeFeedback extends PlayerFeedback {
  const VolumeFeedback({required this.volume, required this.muted});

  final double volume;
  final bool muted;
}

/// G/H: ritardo dei sottotitoli dopo il tasto.
final class SubtitleDelayFeedback extends PlayerFeedback {
  const SubtitleDelayFeedback(this.delay);

  final Duration delay;
}

/// Salto automatico di intro o riassunto (spec D §13).
final class SkipFeedback extends PlayerFeedback {
  const SkipFeedback(this.kind);

  final SkipKind kind;
}

/// Stato dell'interfaccia del player (spec D §5.1): controlli, pannello e
/// riscontro dei tasti. Lo stato della riproduzione resta nel
/// `PlayerController`. Lo crea e lo distrugge `PlayerScreen`.
class PlayerChromeController extends ChangeNotifier {
  /// Mouse fermo per questo tempo, in riproduzione: i controlli spariscono.
  static const hideDelay = Duration(seconds: 3);

  /// Quanto resta la pillola dopo l'ultimo tasto.
  static const feedbackDuration = Duration(milliseconds: 1200);

  /// Salti nella stessa direzione entro questo tempo: si sommano.
  static const seekSumWindow = Duration(seconds: 1);

  /// Nel watch party l'avviso "Hai…" di un'azione arriva fino a 400 ms dopo
  /// il tasto (`GroupAuthority.seekDebounce`): entro questo tempo è la
  /// stessa azione, già mostrata dalla pillola del tasto.
  static const keyActionWindow = Duration(seconds: 1);

  /// In pausa, mouse e tasti fermi per questo tempo: compare la schermata
  /// "Stai guardando" (spec D §11.1).
  static const pauseScreenDelay = Duration(seconds: 8);

  bool _controlsVisible = true;
  bool _panelOpen = false;
  bool _playing = false;
  bool _pauseScreen = false;
  bool _postPlayDismissed = false;

  /// La schermata di pausa è ammessa adesso (lo decide `PlayerScreen`).
  bool _canShowPauseScreen = false;
  PlayerFeedback? _feedback;

  /// Ultimo riscontro e quando è arrivato: restano anche dopo che la
  /// pillola è sparita (somma dei salti, [isRecentKeyAction]).
  PlayerFeedback? _lastFeedback;
  DateTime? _lastFeedbackAt;

  /// Ultimo Spazio (stato dopo il tasto e quando) e ultimo salto: un altro
  /// tasto nel mezzo non li cancella ([isRecentKeyAction]).
  bool? _lastPlaying;
  DateTime? _lastPlayAt;
  DateTime? _lastSeekAt;
  Timer? _hideTimer;
  Timer? _feedbackTimer;
  Timer? _pauseTimer;

  bool get controlsVisible => _controlsVisible;

  bool get panelOpen => _panelOpen;

  /// Schermata "Stai guardando" mostrata.
  bool get pauseScreen => _pauseScreen;

  /// L'utente ha chiuso il post-play o la scheda ("Guarda i titoli",
  /// "Annulla", Esc): per questo episodio non tornano.
  bool get postPlayDismissed => _postPlayDismissed;

  /// Riscontro da mostrare adesso; `null` = nessuno.
  PlayerFeedback? get feedback => _feedback;

  /// Il mouse si è mosso: controlli visibili, schermata di pausa chiusa, e
  /// i conti per nasconderli ripartono.
  void pointerActivity() {
    final changed = !_controlsVisible || _pauseScreen;
    _controlsVisible = true;
    _pauseScreen = false;
    if (changed) notifyListeners();
    _scheduleHide();
  }

  /// Un tasto: chiude la schermata di pausa e fa ripartire il conto, senza
  /// mostrare i controlli (spec D §9.1).
  void keyActivity() {
    if (_pauseScreen) {
      _pauseScreen = false;
      notifyListeners();
    }
    // Il conto riparte solo in pausa (quello degli 8 s). In riproduzione
    // quello dei 3 s è del mouse: tenendo premuta una freccia i controlli
    // resterebbero su.
    if (!_playing) _scheduleHide();
  }

  /// Riproduzione o pausa, e se la schermata di pausa è ammessa adesso:
  /// file pronto e fermo, niente buffering, video non finito, gruppo non in
  /// attesa (lo calcola `PlayerScreen`). In riproduzione, o se non è più
  /// ammessa, la schermata di pausa si chiude.
  void setPlayback({required bool playing, required bool canShowPauseScreen}) {
    if (playing == _playing && canShowPauseScreen == _canShowPauseScreen) {
      return;
    }
    _playing = playing;
    _canShowPauseScreen = canShowPauseScreen;
    if (_pauseScreen && (playing || !canShowPauseScreen)) {
      _pauseScreen = false;
      notifyListeners();
    }
    _scheduleHide();
  }

  /// Apre o chiude il pannello "Audio e sottotitoli": i controlli si vedono
  /// e, a pannello aperto, restano.
  void togglePanel() {
    _panelOpen = !_panelOpen;
    _controlsVisible = true;
    _pauseScreen = false;
    notifyListeners();
    _scheduleHide();
  }

  void closePanel() {
    if (!_panelOpen) return;
    _panelOpen = false;
    notifyListeners();
    _scheduleHide();
  }

  /// Post-play o scheda chiusi: tornano i controlli (e il loro conto).
  void dismissPostPlay() {
    if (_postPlayDismissed) return;
    _postPlayDismissed = true;
    _controlsVisible = true;
    notifyListeners();
    _scheduleHide();
  }

  /// Mostra [feedback] per [feedbackDuration]. I controlli non compaiono.
  void showFeedback(PlayerFeedback feedback) {
    final now = clock.now();
    _feedback = feedback;
    _lastFeedback = feedback;
    _lastFeedbackAt = now;
    if (feedback is PlayFeedback) {
      _lastPlaying = feedback.playing;
      _lastPlayAt = now;
    } else if (feedback is SeekFeedback) {
      _lastSeekAt = now;
    }
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(feedbackDuration, () {
      _feedback = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Salto di [step] da [from]. Se continua una serie nella stessa
  /// direzione (entro [seekSumWindow]) somma l'offset e parte dall'arrivo
  /// precedente. L'arrivo resta tra 0 e [duration] (se nota).
  void seek(Duration step,
      {required Duration from, required Duration duration}) {
    final previous = _lastFeedback;
    final at = _lastFeedbackAt;
    SeekFeedback? series;
    if (previous is SeekFeedback &&
        at != null &&
        clock.now().difference(at) <= seekSumWindow &&
        previous.offset.isNegative == step.isNegative) {
      series = previous;
    }
    final offset = (series?.offset ?? Duration.zero) + step;
    var target = (series?.target ?? from) + step;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    showFeedback(SeekFeedback(offset: offset, target: target));
  }

  /// `true` se un tasto, entro [keyActionWindow], ha fatto la stessa azione
  /// di gruppo [kind]: pausa, ripresa o salto. Ogni azione ha il suo
  /// ultimo tasto: ← poi ↑ (o Spazio) non fa dimenticare il salto.
  bool isRecentKeyAction(PartyNoticeKind kind) {
    bool recent(DateTime? at) =>
        at != null && clock.now().difference(at) <= keyActionWindow;
    return switch (kind) {
      PartyNoticeKind.paused => _lastPlaying == false && recent(_lastPlayAt),
      PartyNoticeKind.resumed => _lastPlaying == true && recent(_lastPlayAt),
      PartyNoticeKind.seeked => recent(_lastSeekAt),
      _ => false,
    };
  }

  /// In riproduzione i controlli si nascondono dopo [hideDelay]; in pausa,
  /// se ammessa, dopo [pauseScreenDelay] compare la schermata di pausa (e i
  /// controlli si nascondono). Con il pannello aperto nessuno dei due.
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    if (_panelOpen) return;
    if (_playing) {
      if (!_controlsVisible) return;
      _hideTimer = Timer(hideDelay, () {
        _controlsVisible = false;
        notifyListeners();
      });
    } else if (_canShowPauseScreen && !_pauseScreen) {
      _pauseTimer = Timer(pauseScreenDelay, () {
        _pauseScreen = true;
        _controlsVisible = false;
        notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    _pauseTimer?.cancel();
    super.dispose();
  }
}
