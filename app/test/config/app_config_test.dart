import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/config/app_config.dart';

AppConfig parse({
  String serverUrl = 'https://media.example.com',
  String supportUrl = 'https://discord.gg/abc',
  String accessRequestUrl = '',
}) =>
    AppConfig.parse(
      serverUrl: serverUrl,
      githubRepo: ' owner/repo ',
      discordAppId: '123',
      supportUrl: supportUrl,
      accessRequestUrl: accessRequestUrl,
    );

void main() {
  group('AppConfig.parse', () {
    test('toglie lo slash finale dall\'indirizzo del server', () {
      final config = parse(serverUrl: 'https://media.example.com/');
      expect(config.serverUrl.toString(), 'https://media.example.com');
      expect(config.githubRepo, 'owner/repo');
      expect(config.discordAppId, '123');
      expect(config.supportUrl, Uri.parse('https://discord.gg/abc'));
    });

    test('mantiene un sottopercorso', () {
      final config = parse(serverUrl: 'https://example.com/jellyfin/');
      expect(config.serverUrl.toString(), 'https://example.com/jellyfin');
    });

    test('supportUrl vuoto diventa null', () {
      expect(parse(supportUrl: '  ').supportUrl, isNull);
    });

    test('accessRequestUrl https letto correttamente', () {
      final config =
          parse(accessRequestUrl: 'https://discord.com/users/1');
      expect(config.accessRequestUrl, Uri.parse('https://discord.com/users/1'));
    });

    test('accessRequestUrl vuoto diventa null', () {
      expect(parse(accessRequestUrl: '  ').accessRequestUrl, isNull);
      expect(parse().accessRequestUrl, isNull);
    });

    test('accessRequestUrl senza schema http(s) diventa null', () {
      expect(parse(accessRequestUrl: 'discord.com/users/1').accessRequestUrl,
          isNull);
      expect(parse(accessRequestUrl: 'javascript:alert(1)').accessRequestUrl,
          isNull);
    });

    test('rifiuta indirizzi non https', () {
      expect(() => parse(serverUrl: 'http://media.example.com'),
          throwsA(isA<AppConfigException>()));
    });

    test('rifiuta indirizzo vuoto', () {
      expect(() => parse(serverUrl: ''), throwsA(isA<AppConfigException>()));
    });
  });
}
