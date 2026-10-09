import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/logging/redact.dart';

void main() {
  test('header MediaBrowser: via il token', () {
    expect(
        redactSecrets('MediaBrowser Client="WonderFlix", Token="abc123"'),
        'MediaBrowser Client="WonderFlix", Token="***"');
  });

  test('parametri dell\'indirizzo', () {
    expect(redactSecrets('GET /Videos/1/stream?api_key=abc&static=true'),
        'GET /Videos/1/stream?api_key=***&static=true');
    expect(redactSecrets('https://x/a?ApiKey=zz'), 'https://x/a?ApiKey=***');
  });

  test('JSON con password e token', () {
    expect(
        redactSecrets(
            '{"Username":"mario","Pw":"segreta","AccessToken": "t0k"}'),
        '{"Username":"mario","Pw":"***","AccessToken":"***"}');
  });

  test('header Authorization scritto per intero', () {
    expect(
        redactSecrets(
            'headers: {Authorization: MediaBrowser Client="W", Token="x"}'),
        'headers: {Authorization: ***');
  });

  test('JSON con virgolette escape nel valore', () {
    expect(redactSecrets(r'{"Pw":"pa\"ss123"}'), '{"Pw":"***"}');
  });

  test('Token="…" in minuscolo', () {
    expect(redactSecrets('MediaBrowser token="abc"'),
        'MediaBrowser token="***"');
  });

  test('nomi dei parametri anche in forma di mappa o JSON', () {
    expect(redactSecrets('{X-Emby-Token: abc}'), '{X-Emby-Token: ***}');
    expect(redactSecrets('{"api_key":"abc","x":1}'),
        '{"api_key":"***","x":1}');
    expect(redactSecrets('{ApiKey: abc, access_token: def}'),
        '{ApiKey: ***, access_token: ***}');
    expect(redactSecrets("{'X-MediaBrowser-Token': 'abc'}"),
        isNot(contains('abc')));
  });

  test('testo senza segreti: invariato', () {
    const text = 'direct play non riuscito: provo la transcodifica';
    expect(redactSecrets(text), text);
  });

  test('corpi del recupero e dei contatti (spec L §8)', () {
    expect(
        redactSecrets('{"Username":"garg","Code":"012345",'
            '"NewPassword":"nuova","CurrentPw":"a","NewPw":"b",'
            '"Target":"a@example.com","Password":"c","Language":"it"}'),
        '{"Username":"garg","Code":"***","NewPassword":"***",'
        '"CurrentPw":"***","NewPw":"***","Target":"***","Password":"***",'
        '"Language":"it"}');
  });

  test('un "Code" numerico resta com\'era: solo il JSON con valore stringa',
      () {
    expect(redactSecrets('{"Code":4000}'), '{"Code":4000}');
  });

  test('la forma a mappa {code: 4000} (i frame di Discord IPC) resta com\'era',
      () {
    expect(redactSecrets('{code: 4000}'), '{code: 4000}');
  });
}
