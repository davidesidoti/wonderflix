import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/video/subtitle_kind.dart';

void main() {
  const base = 'https://h/jellyfin/Videos/1/2/Subtitles/3/0';

  test('tipo dall\'estensione, senza la query', () {
    expect(subtitleKindForUrl('$base/Stream.ass?ApiKey=x'), SubtitleKind.ass);
    expect(subtitleKindForUrl('$base/Stream.vtt'), SubtitleKind.text);
    expect(subtitleKindForUrl('$base/Stream.sup'), SubtitleKind.pgs);
    expect(subtitleKindForUrl('$base/Stream.xyz'), isNull);
  });
}
