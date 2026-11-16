/// Etichette delle tracce e dei formati: un solo posto per codec, lingue e
/// canali (player, Info tecniche, Sottotitoli).
library;

const _twoLetter = {
  'it': 'ita',
  'en': 'eng',
  'ja': 'jpn',
  'fr': 'fre',
  'de': 'ger',
  'es': 'spa',
  'pt': 'por',
  'ko': 'kor',
  'zh': 'chi',
  'ru': 'rus',
};

/// ISO 639-2/T dove differisce da 639-2/B.
const _terminology = {'fra': 'fre', 'deu': 'ger', 'zho': 'chi'};

const _languageNames = {
  'it': {
    'ita': 'Italiano',
    'eng': 'Inglese',
    'jpn': 'Giapponese',
    'fre': 'Francese',
    'ger': 'Tedesco',
    'spa': 'Spagnolo',
    'por': 'Portoghese',
    'kor': 'Coreano',
    'chi': 'Cinese',
    'rus': 'Russo',
  },
  'en': {
    'ita': 'Italian',
    'eng': 'English',
    'jpn': 'Japanese',
    'fre': 'French',
    'ger': 'German',
    'spa': 'Spanish',
    'por': 'Portuguese',
    'kor': 'Korean',
    'chi': 'Chinese',
    'rus': 'Russian',
  },
};

/// Nome della lingua di una traccia ("ita" → "Italiano"); `null` se il
/// codice manca o non lo conosciamo.
String? trackLanguageName(String? code, String localeName) {
  if (code == null) return null;
  var key = code.trim().toLowerCase();
  key = _twoLetter[key] ?? _terminology[key] ?? key;
  final names =
      _languageNames[localeName.split(RegExp('[_-]')).first] ??
      _languageNames['en']!;
  return names[key];
}

/// "HEVC", "E-AC-3", "SRT"; un codec che non conosciamo in maiuscolo.
String codecLabel(String? codec) {
  final key = codec?.trim().toLowerCase() ?? '';
  return switch (key) {
    'hevc' || 'h265' => 'HEVC',
    'h264' || 'avc' => 'H.264',
    'av1' => 'AV1',
    'vp9' => 'VP9',
    'mpeg2video' => 'MPEG-2',
    'eac3' => 'E-AC-3',
    'ac3' => 'AC-3',
    'aac' => 'AAC',
    'dts' => 'DTS',
    'truehd' => 'TrueHD',
    'flac' => 'FLAC',
    'opus' => 'Opus',
    'mp3' => 'MP3',
    'subrip' || 'srt' => 'SRT',
    'ass' || 'ssa' => 'ASS',
    'pgssub' => 'PGS',
    'dvdsub' || 'dvd_subtitle' => 'VobSub',
    'webvtt' || 'vtt' => 'WebVTT',
    _ => key.toUpperCase(),
  };
}

/// "Mono", "2.0", "5.1", "7.1"; `null` per gli altri numeri di canali.
String? channelsLabel(int? channels) => switch (channels) {
  1 => 'Mono',
  2 => '2.0',
  6 => '5.1',
  8 => '7.1',
  _ => null,
};
