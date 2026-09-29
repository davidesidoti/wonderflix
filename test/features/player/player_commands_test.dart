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

  test('il rilascio del tasto non fa nulla', () {
    expect(playerCommandFor(up(LogicalKeyboardKey.space)), isNull);
  });
}
