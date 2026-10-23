import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/media_url.dart';

void main() {
  test('aggiunge ApiKey e tiene gli altri parametri', () {
    final url = withApiKey('https://h/jellyfin/Videos/1/stream?static=true', 't');
    expect(url, contains('static=true'));
    expect(url, contains('ApiKey=t'));
  });

  test('ApiKey già presente (qualunque maiuscola): invariato', () {
    const a = 'https://h/x/master.m3u8?ApiKey=old&a=1';
    expect(withApiKey(a, 'new'), a);
    const b = 'https://h/x?apikey=old';
    expect(withApiKey(b, 'new'), b);
  });

  test('api_key è un altro parametro: ApiKey si aggiunge', () {
    expect(withApiKey('https://h/x?api_key=old', 'new'), contains('ApiKey=new'));
  });
}
