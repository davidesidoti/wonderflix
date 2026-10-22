import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/discord/discord_activity.dart';
import 'package:wonderflix/features/discord/discord_settings.dart';

void main() {
  const labels = DiscordLabels(paused: 'In pausa', button: "Chiedi l'accesso");
  final button = Uri.parse('https://discord.gg/abc');
  final start = DateTime.utc(2026, 9, 29, 21);

  Map<String, Object?> build({
    String? subtitle = 'S1:E4 · Pilot',
    String? poster = 'https://media.example.com/p.jpg',
    bool playing = true,
    DateTime? begin,
    Duration? duration,
    DiscordSettings settings = const DiscordSettings(),
    Uri? buttonUrl,
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
        buttonUrl: buttonUrl,
      );

  test('in riproduzione: titolo, episodio, tempi, locandina, pulsante', () {
    expect(
        build(
            begin: start,
            duration: const Duration(minutes: 47),
            buttonUrl: button),
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
            {'label': "Chiedi l'accesso", 'url': 'https://discord.gg/abc'},
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

  test('senza buttonUrl: nessun pulsante', () {
    expect(build().containsKey('buttons'), isFalse);
  });

  test('buttonUrl non http(s): nessun pulsante', () {
    expect(build(buttonUrl: Uri.parse('discord.gg/abc')).containsKey('buttons'),
        isFalse);
    expect(
        build(buttonUrl: Uri.parse('javascript:alert(1)'))
            .containsKey('buttons'),
        isFalse);
    expect(
        build(buttonUrl: Uri.parse('http://example.com'))
            .containsKey('buttons'),
        isTrue);
  });

  test('discordText: da 2 a 128 caratteri', () {
    expect(discordText('Up'), 'Up');
    expect(discordText('X'), hasLength(2));
    expect(discordText('  M  '), hasLength(2));
    final long = discordText('a' * 200);
    expect(long, hasLength(128));
    expect(long, endsWith('…'));
  });

  test('nel watch party: stato "Watch party · N persone" durante la visione',
      () {
    final partyLabels = DiscordLabels(
      paused: 'In pausa',
      button: "Chiedi l'accesso",
      party: (count) => 'Watch party · $count persone',
    );
    Map<String, Object?> activity({required bool playing, bool showTitle = true}) =>
        buildDiscordActivity(
          title: 'Breaking Bad',
          subtitle: 'S1:E4 · Pilot',
          playing: playing,
          settings: DiscordSettings(showTitle: showTitle),
          labels: partyLabels,
          partySize: 3,
        );
    expect(activity(playing: true)['state'], 'Watch party · 3 persone');
    expect(activity(playing: true, showTitle: false)['state'],
        'Watch party · 3 persone');
    expect(activity(playing: false)['state'], 'In pausa');
    expect(
        buildDiscordActivity(
          title: 'Breaking Bad',
          subtitle: 'S1:E4 · Pilot',
          playing: true,
          settings: const DiscordSettings(),
          labels: partyLabels,
        )['state'],
        'S1:E4 · Pilot',
        reason: 'fuori da un gruppo non cambia nulla');
  });
}
