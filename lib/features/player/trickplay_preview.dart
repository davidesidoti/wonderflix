import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import 'player_providers.dart';
import 'trickplay.dart';

/// Una cella di un mosaico trickplay, ridimensionata a [width].
class TrickplayPreview extends ConsumerWidget {
  const TrickplayPreview({
    super.key,
    required this.url,
    required this.info,
    required this.tile,
    this.width = 240,
  });

  final String url;
  final TrickplayInfo info;
  final TrickplayTile tile;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (info.width <= 0 || info.height <= 0) return const SizedBox.shrink();
    final scale = width / info.width;
    final cellWidth = info.width * scale;
    final cellHeight = info.height * scale;
    final sheetWidth = cellWidth * info.tileWidth;
    final sheetHeight = cellHeight * info.tileHeight;
    return SizedBox(
      width: cellWidth,
      height: cellHeight,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          minHeight: 0,
          maxWidth: sheetWidth,
          maxHeight: sheetHeight,
          child: Transform.translate(
            offset: Offset(-tile.column * cellWidth, -tile.row * cellHeight),
            // - solo la larghezza: l'ultimo mosaico può avere meno righe e
            //   non va deformato;
            // - chiave per URL: mentre carica un mosaico nuovo non si vede il
            //   vecchio con le coordinate della cella nuova;
            // - decodificato alla larghezza mostrata (mai oltre quella
            //   originale), per non tenere in memoria mosaici più grandi del
            //   necessario.
            child: Image(
              key: ValueKey(url),
              image: ResizeImage(ref.watch(authImageProvider)(url),
                  width: (sheetWidth * MediaQuery.devicePixelRatioOf(context))
                      .round()),
              width: sheetWidth,
              fit: BoxFit.fitWidth,
              alignment: Alignment.topLeft,
            ),
          ),
        ),
      ),
    );
  }
}
