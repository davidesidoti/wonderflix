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
/// nella larghezza più vicina a [preferredWidth], con la sorgente a cui
/// appartengono: è quella da indicare nell'URL dei mosaici.
({String mediaSourceId, TrickplayInfo info})? pickTrickplay(
    JellyfinItem item, String mediaSourceId,
    {int preferredWidth = 320}) {
  final sourceId = item.trickplay.containsKey(mediaSourceId)
      ? mediaSourceId
      : item.trickplay.keys.firstOrNull;
  if (sourceId == null) return null;
  TrickplayInfo? best;
  for (final info in item.trickplay[sourceId]!.values) {
    if (best == null ||
        (info.width - preferredWidth).abs() <
            (best.width - preferredWidth).abs()) {
      best = info;
    }
  }
  return best == null ? null : (mediaSourceId: sourceId, info: best);
}

/// Anteprima da mostrare per [position]; `null` se non ci sono anteprime (o
/// i dati non sono validi).
TrickplayTile? trickplayTileAt(TrickplayInfo info, Duration position) {
  final perSheet = info.tileWidth * info.tileHeight;
  if (info.width <= 0 ||
      info.height <= 0 ||
      info.interval <= Duration.zero ||
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
