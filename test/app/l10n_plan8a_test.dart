import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 8a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.playerFeedbackPlaying, 'Riproduzione');
    expect(it.playerFeedbackPaused, 'In pausa');
    expect(it.playerFeedbackSeek('+20 s', '18:02'), '+20 s · 18:02');
    expect(it.playerFeedbackVolume(70), 'Volume 70%');
    expect(it.playerFeedbackMuted, 'Audio disattivato');
    expect(it.playerFeedbackSubtitles('+0,3 s'), 'Sottotitoli +0,3 s');
    expect(it.playerSegmentRecap, 'Riassunto');
    expect(it.playerSegmentIntro, 'Intro');
    expect(it.playerSegmentOutro, 'Titoli di coda');
    expect(en.playerFeedbackPlaying, 'Playing');
    expect(en.playerFeedbackPaused, 'Paused');
    expect(en.playerFeedbackSeek('-10 s', '17:32'), '-10 s · 17:32');
    expect(en.playerFeedbackVolume(70), 'Volume 70%');
    expect(en.playerFeedbackMuted, 'Muted');
    expect(en.playerFeedbackSubtitles('+0.3 s'), 'Subtitles +0.3 s');
    expect(en.playerSegmentRecap, 'Recap');
    expect(en.playerSegmentIntro, 'Intro');
    expect(en.playerSegmentOutro, 'End credits');
  });
}
