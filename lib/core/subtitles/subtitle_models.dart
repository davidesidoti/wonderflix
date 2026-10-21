import 'dart:typed_data';

/// Un sottotitolo trovato dai provider (`RemoteSubtitleDto`, spec R §6.4).
/// Nome e provider sono testo dei provider: si mostrano come testo semplice.
class RemoteSubtitle {
  const RemoteSubtitle({
    required this.id,
    required this.providerName,
    required this.name,
    required this.language,
    required this.format,
    this.communityRating,
    this.downloadCount,
    this.isHashMatch = false,
    this.hearingImpaired = false,
    this.forced = false,
    this.machineTranslated = false,
  });

  factory RemoteSubtitle.fromJson(Map<dynamic, dynamic> json) => RemoteSubtitle(
        id: json['Id'] as String,
        providerName: json['ProviderName'] as String? ?? '',
        name: json['Name'] as String? ?? '',
        language: json['Language'] as String? ?? '',
        format: json['Format'] as String? ?? '',
        communityRating: (json['CommunityRating'] as num?)?.toDouble(),
        downloadCount: (json['DownloadCount'] as num?)?.toInt(),
        isHashMatch: json['IsHashMatch'] == true,
        hearingImpaired: json['HearingImpaired'] == true,
        forced: json['Forced'] == true,
        machineTranslated: json['MachineTranslated'] == true,
      );

  final String id;
  final String providerName;
  final String name;
  final String language;
  final String format;
  final double? communityRating;
  final int? downloadCount;

  /// Sincronizzato col file (hash).
  final bool isHashMatch;
  final bool hearingImpaired;
  final bool forced;
  final bool machineTranslated;
}

/// Prima i sincronizzati col file, poi per download decrescenti (senza il
/// numero in fondo), a parità per nome.
List<RemoteSubtitle> sortSubtitles(Iterable<RemoteSubtitle> subtitles) =>
    subtitles.toList()
      ..sort((a, b) {
        if (a.isHashMatch != b.isHashMatch) return a.isHashMatch ? -1 : 1;
        final downloadsA = a.downloadCount;
        final downloadsB = b.downloadCount;
        if (downloadsA != downloadsB) {
          if (downloadsA == null) return 1;
          if (downloadsB == null) return -1;
          return downloadsB.compareTo(downloadsA);
        }
        return a.name.compareTo(b.name);
      });

/// Un file di sottotitoli da caricare (spec R §6.4).
class SubtitleUpload {
  const SubtitleUpload({
    required this.language,
    required this.format,
    this.isForced = false,
    this.isHearingImpaired = false,
    required this.bytes,
  });

  /// Codice a tre lettere.
  final String language;

  /// L'estensione del file: `srt`, `ass`, `ssa`, `vtt` o `sub`.
  final String format;
  final bool isForced;
  final bool isHearingImpaired;
  final Uint8List bytes;
}
