import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/player/player_commands.dart';

KeyEvent down(LogicalKeyboardKey key) => KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero);

KeyEvent repeat(LogicalKeyboardKey key) => KeyRepeatEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero);

KeyEvent up(LogicalKeyboardKey key) => KeyUpEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero);

void main() {
  test('tasti della spec', () {
    expect(playerCommandFor(down(LogicalKeyboardKey.space)),
        PlayerCommand.togglePlay);
    expect(playerCommandFor(down(LogicalKeyboardKey.mediaPlayPause)),
        PlayerCommand.togglePlay);
    expect(playerCommandFor(down(LogicalKeyboardKey.arrowLeft)),
        PlayerCommand.seekBack);
    expect(playerCommandFor(down(LogicalKeyboardKey.arrowRight)),
        PlayerCommand.seekForward);
    expect(playerCommandFor(down(LogicalKeyboardKey.arrowUp)),
        PlayerCommand.volumeUp);
    expect(playerCommandFor(down(LogicalKeyboardKey.arrowDown)),
        PlayerCommand.volumeDown);
    expect(playerCommandFor(down(LogicalKeyboardKey.keyF)),
        PlayerCommand.toggleFullscreen);
    expect(playerCommandFor(down(LogicalKeyboardKey.keyM)),
        PlayerCommand.toggleMute);
    expect(playerCommandFor(down(LogicalKeyboardKey.keyG)),
        PlayerCommand.subtitleDelayDown);
    expect(playerCommandFor(down(LogicalKeyboardKey.keyH)),
        PlayerCommand.subtitleDelayUp);
    expect(playerCommandFor(down(LogicalKeyboardKey.escape)),
        PlayerCommand.escape);
    expect(playerCommandFor(down(LogicalKeyboardKey.browserBack)),
        PlayerCommand.exit);
    expect(playerCommandFor(down(LogicalKeyboardKey.mediaStop)),
        PlayerCommand.exit);
    expect(playerCommandFor(down(LogicalKeyboardKey.keyN)),
        PlayerCommand.nextEpisode);
    expect(playerCommandFor(down(LogicalKeyboardKey.mediaTrackNext)),
        PlayerCommand.nextEpisode);
    expect(playerCommandFor(down(LogicalKeyboardKey.keyQ)), isNull);
  });

  test('Alt+← esce; con Alt gli altri tasti sono ignorati', () {
    expect(
        playerCommandFor(down(LogicalKeyboardKey.arrowLeft), altPressed: true),
        PlayerCommand.exit);
    expect(playerCommandFor(down(LogicalKeyboardKey.space), altPressed: true),
        isNull);
  });

  test('tasto tenuto premuto: si ripetono solo salti, volume e ritardo', () {
    expect(playerCommandFor(repeat(LogicalKeyboardKey.arrowRight)),
        PlayerCommand.seekForward);
    expect(playerCommandFor(repeat(LogicalKeyboardKey.arrowUp)),
        PlayerCommand.volumeUp);
    expect(playerCommandFor(repeat(LogicalKeyboardKey.keyH)),
        PlayerCommand.subtitleDelayUp);
    expect(playerCommandFor(repeat(LogicalKeyboardKey.space)), isNull);
    expect(playerCommandFor(repeat(LogicalKeyboardKey.keyF)), isNull);
    expect(
        playerCommandFor(repeat(LogicalKeyboardKey.arrowLeft), altPressed: true),
        isNull);
  });

  test('tasti multimediali ignorati se li gestisce la sessione media', () {
    for (final key in [
      LogicalKeyboardKey.mediaPlayPause,
      LogicalKeyboardKey.mediaTrackNext,
      LogicalKeyboardKey.mediaStop,
    ]) {
      expect(playerCommandFor(down(key), mediaKeys: false), isNull);
    }
    expect(playerCommandFor(down(LogicalKeyboardKey.space), mediaKeys: false),
        PlayerCommand.togglePlay);
    expect(playerCommandFor(down(LogicalKeyboardKey.keyN), mediaKeys: false),
        PlayerCommand.nextEpisode);
    expect(
        playerCommandFor(down(LogicalKeyboardKey.escape), mediaKeys: false),
        PlayerCommand.escape);
  });

  test('il rilascio del tasto non fa nulla', () {
    expect(playerCommandFor(up(LogicalKeyboardKey.space)), isNull);
  });

  test('P e il tasto multimediale "indietro": precedente (spec H §9.1)', () {
    expect(playerCommandFor(down(LogicalKeyboardKey.keyP)),
        PlayerCommand.previous);
    expect(playerCommandFor(down(LogicalKeyboardKey.mediaTrackPrevious)),
        PlayerCommand.previous);
    expect(isMediaKey(LogicalKeyboardKey.mediaTrackPrevious), isTrue);
    expect(
        playerCommandFor(down(LogicalKeyboardKey.mediaTrackPrevious),
            mediaKeys: false),
        isNull,
        reason: 'lo riceve già la sessione media di sistema');
    expect(playerCommandFor(repeat(LogicalKeyboardKey.keyP)), isNull);
  });
}
