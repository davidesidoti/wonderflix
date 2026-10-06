import 'api_exception.dart';
import 'json_fields.dart';

/// Gravità di una voce del registro (`LogLevel`): Trace, Debug e
/// Information sono informazioni, Critical è un errore.
enum ActivitySeverity { info, warning, error }

/// Una voce del registro attività (`ActivityLogEntry`, spec J §8.2).
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.name,
    this.shortOverview,
    this.overview,
    this.type,
    this.itemId,
    this.date,
    this.userId,
    this.severity = ActivitySeverity.info,
  });

  /// `null` senza `Id`.
  static ActivityEntry? fromJson(Map<String, dynamic> json) {
    final id = jsonInt(json, 'Id');
    if (id == null) return null;
    // Le voci di sistema hanno un utente (e a volte un elemento) di soli zeri.
    String? realId(String key) {
      final value = jsonString(json, key);
      return value == null || isEmptyJellyfinId(value) ? null : value;
    }

    return ActivityEntry(
      id: id,
      name: jsonString(json, 'Name') ?? '',
      shortOverview: jsonString(json, 'ShortOverview'),
      overview: jsonString(json, 'Overview'),
      type: jsonString(json, 'Type'),
      itemId: realId('ItemId'),
      date: jsonDate(json, 'Date'),
      userId: realId('UserId'),
      severity: switch (json['Severity']) {
        'Warning' => ActivitySeverity.warning,
        'Error' || 'Critical' => ActivitySeverity.error,
        _ => ActivitySeverity.info,
      },
    );
  }

  final int id;
  final String name;
  final String? shortOverview;
  final String? overview;
  final String? type;

  /// Il titolo della voce (una riproduzione), se c'è.
  final String? itemId;
  final DateTime? date;

  /// `null` per le voci di sistema.
  final String? userId;
  final ActivitySeverity severity;
}

/// Una pagina del registro: le voci e quante sono in tutto con quel filtro.
class ActivityPage {
  const ActivityPage({required this.items, required this.total});

  final List<ActivityEntry> items;
  final int total;
}

/// `{Items, TotalRecordCount, StartIndex}`; senza `TotalRecordCount` il
/// totale è il numero delle voci lette.
ActivityPage parseActivityPage(Object? data) {
  if (data is! Map<String, dynamic>) throw const ServerErrorException(null);
  final items = jsonList(data['Items'], ActivityEntry.fromJson);
  return ActivityPage(
      items: items, total: jsonInt(data, 'TotalRecordCount') ?? items.length);
}
