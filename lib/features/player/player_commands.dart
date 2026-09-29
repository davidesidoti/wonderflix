import 'package:flutter/services.dart';

/// Salto di ←/→ e dei pulsanti.
const seekStep = Duration(seconds: 10);

/// Passo del volume con ↑/↓ (scala 0–100).
const volumeStep = 5.0;

/// Passo del ritardo dei sottotitoli con G/H.
const subtitleDelayStep = Duration(milliseconds: 100);

enum PlayerCommand {
  togglePlay,
  seekBack,
  seekForward,
  volumeUp,
  volumeDown,
  toggleFullscreen,
  toggleMute,
  subtitleDelayDown,
  subtitleDelayUp,

  /// Esc: chiude il pannello, poi esce dallo schermo intero, poi dal player.
  escape,

  /// Esce subito dal player.
  exit,
}

// Non `const`: le chiavi ridefiniscono `==`.
final _commands = <LogicalKeyboardKey, PlayerCommand>{
  LogicalKeyboardKey.space: PlayerCommand.togglePlay,
  LogicalKeyboardKey.mediaPlayPause: PlayerCommand.togglePlay,
  LogicalKeyboardKey.arrowLeft: PlayerCommand.seekBack,
  LogicalKeyboardKey.arrowRight: PlayerCommand.seekForward,
  LogicalKeyboardKey.arrowUp: PlayerCommand.volumeUp,
  LogicalKeyboardKey.arrowDown: PlayerCommand.volumeDown,
  LogicalKeyboardKey.keyF: PlayerCommand.toggleFullscreen,
  LogicalKeyboardKey.keyM: PlayerCommand.toggleMute,
  LogicalKeyboardKey.keyG: PlayerCommand.subtitleDelayDown,
  LogicalKeyboardKey.keyH: PlayerCommand.subtitleDelayUp,
  LogicalKeyboardKey.escape: PlayerCommand.escape,
  LogicalKeyboardKey.browserBack: PlayerCommand.exit,
  LogicalKeyboardKey.mediaStop: PlayerCommand.exit,
};

/// Comandi che si ripetono tenendo premuto il tasto.
const _repeatable = {
  PlayerCommand.seekBack,
  PlayerCommand.seekForward,
  PlayerCommand.volumeUp,
  PlayerCommand.volumeDown,
  PlayerCommand.subtitleDelayDown,
  PlayerCommand.subtitleDelayUp,
};

/// Comando del player per un evento di tastiera; `null` se il tasto non è
/// gestito. Con Alt premuto vale solo Alt+← (esci).
PlayerCommand? playerCommandFor(KeyEvent event, {bool altPressed = false}) {
  if (event is KeyUpEvent) return null;
  final repeat = event is KeyRepeatEvent;
  if (altPressed) {
    return !repeat && event.logicalKey == LogicalKeyboardKey.arrowLeft
        ? PlayerCommand.exit
        : null;
  }
  final command = _commands[event.logicalKey];
  if (command == null || (repeat && !_repeatable.contains(command))) {
    return null;
  }
  return command;
}
