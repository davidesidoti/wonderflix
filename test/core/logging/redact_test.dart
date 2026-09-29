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

  test('testo senza segreti: invariato', () {
    const text = 'direct play non riuscito: provo la transcodifica';
    expect(redactSecrets(text), text);
  });
}
