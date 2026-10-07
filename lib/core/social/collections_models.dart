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
  /// valore di partenza (nome vuoto, `SortName` dal nome in minuscolo). Gli
  /// `ItemIds` si normalizzano con [jellyfinIdKey] e si tolgono i doppioni.
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
      // Si guarda il tipo qui e non si passa il valore a `jsonStrings`: una
      // stringa con le virgole, per quella funzione un elenco, per il plugin
      // non è un `ItemIds` valido. Il set tiene l'ordine di inserimento.
      itemIds: switch (json['ItemIds']) {
        final List<dynamic> ids => {
            for (final id in jsonStrings(ids)) jellyfinIdKey(id),
          }.toList(),
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

  /// I titoli della saga che l'utente vede: id confrontabili
  /// ([jellyfinIdKey]), senza doppioni.
  final List<String> itemIds;

  /// Quanti titoli distinti ha la saga.
  int get size => itemIds.length;
}
