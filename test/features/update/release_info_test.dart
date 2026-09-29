import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:wonderflix/features/update/release_info.dart';

Map<String, dynamic> releaseJson({
  String tag = 'v0.2.0',
  String body = '## Novità\n- Più veloce',
  bool draft = false,
  bool prerelease = false,
  List<String>? assets,
}) =>
    {
      'tag_name': tag,
      'body': body,
      'draft': draft,
      'prerelease': prerelease,
      'assets': [
        for (final name in assets ??
            [
              'WonderFlix-Setup-0.2.0.exe',
              'WonderFlix-Setup-0.2.0.exe.sha256',
            ])
          {
            'name': name,
            'browser_download_url': 'https://github.com/o/r/releases/download/$tag/$name',
          },
      ],
    };

void main() {
  test('parseRelease: versione, note, installer e checksum', () {
    final release = parseRelease(releaseJson())!;
    expect(release.version, Version(0, 2, 0));
    expect(release.notes, '## Novità\n- Più veloce');
    expect(release.minVersion, isNull);
    expect(release.installerName, 'WonderFlix-Setup-0.2.0.exe');
    expect(release.installerUrl.toString(),
        'https://github.com/o/r/releases/download/v0.2.0/WonderFlix-Setup-0.2.0.exe');
    expect(release.checksumUrl.path, endsWith('WonderFlix-Setup-0.2.0.exe.sha256'));
  });

  test('parseRelease: tag senza "v"', () {
    expect(parseRelease(releaseJson(tag: '0.2.0'))!.version, Version(0, 2, 0));
  });

  test('parseRelease: bozze, pre-release e tag non validi vengono ignorati', () {
    expect(parseRelease(releaseJson(draft: true)), isNull);
    expect(parseRelease(releaseJson(prerelease: true)), isNull);
    expect(parseRelease(releaseJson(tag: 'v0.2.0-beta.1')), isNull);
    expect(parseRelease(releaseJson(tag: 'nightly')), isNull);
  });

  test('parseRelease: senza installer o checksum non c\'è aggiornamento', () {
    expect(parseRelease(releaseJson(assets: ['WonderFlix-Setup-0.2.0.exe'])),
        isNull);
    expect(
        parseRelease(releaseJson(assets: ['WonderFlix-Setup-0.2.0.exe.sha256'])),
        isNull);
  });

  test('marcatore min-version: letto e tolto dalle note', () {
    const body = 'Correzione importante.\n\n<!-- wonderflix:min-version=0.2.0 -->';
    final release = parseRelease(releaseJson(body: body))!;
    expect(release.minVersion, Version(0, 2, 0));
    expect(release.notes, 'Correzione importante.');
    expect(minVersionFrom('<!--wonderflix:min-version=1.0.0-->'), Version(1, 0, 0));
    expect(minVersionFrom('<!-- wonderflix:min-version=boh -->'), isNull);
    expect(minVersionFrom('nessun marcatore'), isNull);
  });

  test('parseSha256File: hash in minuscolo, anche con nome e spazi', () {
    const hash =
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    expect(parseSha256File('$hash  WonderFlix-Setup-0.2.0.exe\n'), hash);
    expect(parseSha256File(hash.toUpperCase()), hash);
    expect(parseSha256File('non un hash'), isNull);
    expect(parseSha256File(''), isNull);
  });

  test('sha256OfFile', () async {
    final temp = Directory.systemTemp.createTempSync('wf_sha_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}${Platform.pathSeparator}a.txt')
      ..writeAsStringSync('abc');
    expect(await sha256OfFile(file),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
}
