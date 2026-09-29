import 'discord_settings.dart';

/// Tipo di attività "Watching" di Discord.
const watchingActivityType = 3;

/// Asset caricato sul Discord Developer Portal.
const discordLogoAsset = 'logo';

/// Testi dell'attività, nella lingua dell'app (li vedono gli amici).
class DiscordLabels {
  const DiscordLabels({required this.paused, required this.button});

  final String paused;

  /// Etichetta del pulsante verso `buttonUrl` (max 32 caratteri).
  final String button;
}

/// Attività di Discord per quello che si sta guardando.
///
/// [start] è l'istante in cui il video sarebbe partito da zero (adesso meno
/// la posizione): con [duration] Discord mostra tempo trascorso e
/// rimanente. In pausa i tempi non si mostrano.
Map<String, Object?> buildDiscordActivity({
  required String title,
  String? subtitle,
  String? posterUrl,
  required bool playing,
  DateTime? start,
  Duration? duration,
  required DiscordSettings settings,
  required DiscordLabels labels,
  Uri? buttonUrl,
}) {
  final showTitle = settings.showTitle;
  // La locandina svela il titolo: senza titolo, sempre il logo.
  final poster = settings.showPoster && showTitle ? posterUrl : null;
  final state = playing ? (showTitle ? subtitle : null) : labels.paused;
  final begin = playing ? start : null;
  final end = begin != null && duration != null && duration > Duration.zero
      ? begin.add(duration)
      : null;
  return {
    'type': watchingActivityType,
    if (showTitle) 'details': discordText(title),
    if (state != null && state.trim().isNotEmpty) 'state': discordText(state),
    if (begin != null)
      'timestamps': {
        'start': begin.millisecondsSinceEpoch,
        'end': ?end?.millisecondsSinceEpoch,
      },
    'assets': {
      'large_image': poster ?? discordLogoAsset,
      'large_text': showTitle ? discordText(title) : 'WonderFlix',
    },
    // Discord accetta solo link web nei pulsanti.
    if (buttonUrl != null &&
        (buttonUrl.isScheme('https') || buttonUrl.isScheme('http')))
      'buttons': [
        {'label': labels.button, 'url': buttonUrl.toString()},
      ],
  };
}

/// Discord accetta testi da 2 a 128 caratteri.
String discordText(String text) {
  final trimmed = text.trim();
  if (trimmed.length > 128) return '${trimmed.substring(0, 127)}…';
  // Spazio vuoto braille: Discord non lo toglie come uno spazio normale.
  return trimmed.padRight(2, '⠀');
}
