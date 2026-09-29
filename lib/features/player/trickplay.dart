import '../../core/jellyfin/item_models.dart';

/// Posizione di un'anteprima: mosaico (immagine) e cella dentro il mosaico.
class TrickplayTile {
  const TrickplayTile({
    required this.sheet,
    required this.column,
    required this.row,
  });

  final int sheet;
  final int column;
  final int row;
}

/// Anteprime della sorgente [mediaSourceId] (o della prima disponibile),
/// nella larghezza più vicina a [preferredWidth].
TrickplayInfo? pickTrickplay(JellyfinItem item, String mediaSourceId,
    {int preferredWidth = 320}) {
  final byWidth =
      item.trickplay[mediaSourceId] ?? item.trickplay.values.firstOrNull;
  if (byWidth == null) return null;
  TrickplayInfo? best;
  for (final info in byWidth.values) {
    if (best == null ||
        (info.width - preferredWidth).abs() <
            (best.width - preferredWidth).abs()) {
      best = info;
    }
  }
  return best;
}

/// Anteprima da mostrare per [position]; `null` se non ci sono anteprime.
TrickplayTile? trickplayTileAt(TrickplayInfo info, Duration position) {
  final perSheet = info.tileWidth * info.tileHeight;
  if (info.interval <= Duration.zero ||
      info.thumbnailCount <= 0 ||
      perSheet <= 0) {
    return null;
  }
  final index = (position.inMilliseconds ~/ info.interval.inMilliseconds)
      .clamp(0, info.thumbnailCount - 1);
  final inSheet = index % perSheet;
  return TrickplayTile(
    sheet: index ~/ perSheet,
    column: inSheet % info.tileWidth,
    row: inSheet ~/ info.tileWidth,
  );
}

/// URL di un mosaico (richiede l'header di autenticazione).
String trickplaySheetUrl(
  Uri serverUrl, {
  required String itemId,
  required int width,
  required int sheet,
  required String mediaSourceId,
}) =>
    Uri.parse('$serverUrl/Videos/$itemId/Trickplay/$width/$sheet.jpg')
        .replace(queryParameters: {'mediaSourceId': mediaSourceId}).toString();
