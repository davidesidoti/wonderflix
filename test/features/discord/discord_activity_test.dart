import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/discord/discord_activity.dart';
import 'package:wonderflix/features/discord/discord_settings.dart';

void main() {
  const labels = DiscordLabels(paused: 'In pausa', button: 'Entra in WonderFlix');
  final support = Uri.parse('https://discord.gg/abc');
  final start = DateTime.utc(2026, 9, 29, 21);

  Map<String, Object?> build({
    String? subtitle = 'S1:E4 · Pilot',
    String? poster = 'https://media.example.com/p.jpg',
    bool playing = true,
    DateTime? begin,
    Duration? duration,
    DiscordSettings settings = const DiscordSettings(),
    Uri? supportUrl,
  }) =>
      buildDiscordActivity(
        title: 'Breaking Bad',
        subtitle: subtitle,
        posterUrl: poster,
        playing: playing,
        start: begin,
        duration: duration,
        settings: settings,
        labels: labels,
        supportUrl: supportUrl,
      );

  test('in riproduzione: titolo, episodio, tempi, locandina, pulsante', () {
    expect(
        build(
            begin: start,
            duration: const Duration(minutes: 47),
            supportUrl: support),
        {
          'type': 3,
          'details': 'Breaking Bad',
          'state': 'S1:E4 · Pilot',
          'timestamps': {
            'start': start.millisecondsSinceEpoch,
            'end': start.add(const Duration(minutes: 47)).millisecondsSinceEpoch,
          },
          'assets': {
            'large_image': 'https://media.example.com/p.jpg',
            'large_text': 'Breaking Bad',
          },
          'buttons': [
            {'label': 'Entra in WonderFlix', 'url': 'https://discord.gg/abc'},
          ],
        });
  });

  test('in pausa: "In pausa" e nessun tempo', () {
    final activity = build(playing: false, begin: start);
    expect(activity['state'], 'In pausa');
    expect(activity.containsKey('timestamps'), isFalse);
  });

  test('senza durata: solo il tempo trascorso', () {
    expect(build(begin: start)['timestamps'],
        {'start': start.millisecondsSinceEpoch});
  });

  test('senza locandina, o con "mostra locandina" spento: il logo', () {
    expect((build(poster: null)['assets'] as Map)['large_image'], 'logo');
    expect(
        (build(settings: const DiscordSettings(showPoster: false))['assets']
            as Map)['large_image'],
        'logo');
  });

  test('"mostra titolo" spento: niente titolo, episodio né locandina', () {
    final activity = build(settings: const DiscordSettings(showTitle: false));
    expect(activity.containsKey('details'), isFalse);
    expect(activity.containsKey('state'), isFalse);
    expect(activity['assets'],
        {'large_image': 'logo', 'large_text': 'WonderFlix'});
  });

  test('senza supportUrl: nessun pulsante', () {
    expect(build().containsKey('buttons'), isFalse);
  });

  test('discordText: da 2 a 128 caratteri', () {
    expect(discordText('Up'), 'Up');
    expect(discordText('X'), hasLength(2));
    expect(discordText('  M  '), hasLength(2));
    final long = discordText('a' * 200);
    expect(long, hasLength(128));
    expect(long, endsWith('…'));
  });
}
