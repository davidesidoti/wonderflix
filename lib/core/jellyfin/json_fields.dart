import 'api_exception.dart';

// Letture tolleranti dei JSON di Jellyfin e del plugin (spec J §8.2): un
// campo mancante o di tipo sbagliato vale `null` (o vuoto) e non fa fallire
// la lettura dell'elenco.

/// Tick di Jellyfin in un microsecondo (10 milioni al secondo).
const _ticksPerMicrosecond = 10;

/// Una stringa non vuota.
String? jsonString(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String && value.isNotEmpty ? value : null;
}

int? jsonInt(Map<String, dynamic> json, String key) => switch (json[key]) {
      final int value => value,
      final double value => value.round(),
      _ => null,
    };

double? jsonDouble(Map<String, dynamic> json, String key) =>
    switch (json[key]) {
      final num value => value.toDouble(),
      _ => null,
    };

DateTime? jsonDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? DateTime.tryParse(value) : null;
}

/// Una durata in tick di Jellyfin.
Duration? jsonTicks(Map<String, dynamic> json, String key) {
  final ticks = jsonInt(json, key);
  return ticks == null
      ? null
      : Duration(microseconds: ticks ~/ _ticksPerMicrosecond);
}

Map<String, dynamic>? jsonMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

/// Stringhe di un elenco JSON; una stringa sola con le virgole (forma di
/// alcune versioni di Jellyfin) vale come elenco.
List<String> jsonStrings(Object? value) => switch (value) {
      final List<dynamic> list => [
          for (final item in list)
            if (item is String && item.isNotEmpty) item,
        ],
      final String text => [
          for (final item in text.split(','))
            if (item.trim().isNotEmpty) item.trim(),
        ],
      _ => const [],
    };

/// Un id di Jellyfin di soli zeri, con o senza trattini: nessuno (per
/// esempio l'utente delle voci di sistema o delle chiavi API).
bool isEmptyJellyfinId(String id) => id.replaceAll(RegExp('[-0]'), '').isEmpty;

/// Un elenco JSON di oggetti. Le voci che [parse] scarta (`null`) e quelle
/// che non sono oggetti si saltano; un corpo che non è un elenco è una
/// risposta inattesa.
List<T> jsonList<T>(
    Object? data, T? Function(Map<String, dynamic> json) parse) {
  if (data is! List) throw const ServerErrorException(null);
  return [
    for (final raw in data)
      if (jsonMap(raw) case final json?) ?parse(json),
  ];
}
