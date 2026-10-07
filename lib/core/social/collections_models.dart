import '../jellyfin/json_fields.dart';

/// Una saga (collezione di Jellyfin) come la dà il plugin (spec K §7.1).
class CollectionSummary {
  const CollectionSummary({
    required this.id,
    required this.name,
    required this.sortName,
    this.primaryImageTag,
    this.dateCreated,
    this.itemIds = const [],
  });

  /// `null` senza `Id`: la voce si scarta. Gli altri campi mancanti hanno un
  /// valore di partenza (nome vuoto, `SortName` dal nome in minuscolo).
  static CollectionSummary? fromJson(Map<String, dynamic> json) {
    final id = jsonString(json, 'Id');
    if (id == null) return null;
    final name = jsonString(json, 'Name') ?? '';
    return CollectionSummary(
      id: id,
      name: name,
      sortName: jsonString(json, 'SortName') ?? name.toLowerCase(),
      primaryImageTag: jsonString(json, 'PrimaryImageTag'),
      dateCreated: jsonDate(json, 'DateCreated'),
      itemIds: switch (json['ItemIds']) {
        final List<dynamic> ids => jsonStrings(ids),
        _ => const [],
      },
    );
  }

  final String id;
  final String name;

  /// Chiave d'ordinamento di Jellyfin.
  final String sortName;

  /// Tag della locandina; `null` senza locandina.
  final String? primaryImageTag;

  /// Aggiunta alla libreria.
  final DateTime? dateCreated;

  /// I titoli della saga che l'utente vede.
  final List<String> itemIds;

  /// Quanti titoli ha la saga.
  int get size => itemIds.length;
}
