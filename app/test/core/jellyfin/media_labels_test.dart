import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/media_labels.dart';

void main() {
  test('trackLanguageName', () {
    expect(trackLanguageName('eng', 'it'), 'Inglese');
    expect(trackLanguageName('ita', 'it'), 'Italiano');
    expect(trackLanguageName('it', 'it'), 'Italiano');
    expect(trackLanguageName('fra', 'it'), 'Francese');
    expect(trackLanguageName('deu', 'en'), 'German');
    expect(trackLanguageName('zh', 'en_US'), 'Chinese');
    expect(trackLanguageName('JPN', 'en'), 'Japanese');
    expect(trackLanguageName('xyz', 'it'), isNull);
    expect(trackLanguageName('', 'it'), isNull);
    expect(trackLanguageName(null, 'it'), isNull);
  });

  test('codecLabel', () {
    expect(codecLabel('hevc'), 'HEVC');
    expect(codecLabel('h264'), 'H.264');
    expect(codecLabel('eac3'), 'E-AC-3');
    expect(codecLabel('ac3'), 'AC-3');
    expect(codecLabel('subrip'), 'SRT');
    expect(codecLabel('dvd_subtitle'), 'VobSub');
    expect(codecLabel('pgssub'), 'PGS');
    expect(codecLabel('mpeg4'), 'MPEG4');
    expect(codecLabel(null), '');
    expect(codecLabel(''), '');
  });

  test('channelsLabel', () {
    expect(channelsLabel(1), 'Mono');
    expect(channelsLabel(2), '2.0');
    expect(channelsLabel(6), '5.1');
    expect(channelsLabel(8), '7.1');
    expect(channelsLabel(3), isNull);
    expect(channelsLabel(null), isNull);
  });

  test('languageName e resolutionLabel', () {
    expect(languageName('ita', 'it'), 'Italiano');
    expect(languageName('eng', 'it'), 'Inglese');
    expect(languageName('swe', 'it'), 'SWE');
    expect(languageName(null, 'it'), '');
    expect(resolutionLabel(3840), '4K');
    expect(resolutionLabel(1920), '1080p');
    expect(resolutionLabel(1280), '720p');
    expect(resolutionLabel(720), isNull);
    expect(resolutionLabel(null), isNull);
  });
}
