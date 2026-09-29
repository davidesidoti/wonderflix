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
            child: Image(
              image: ref.watch(authImageProvider)(url),
              width: sheetWidth,
              height: sheetHeight,
              fit: BoxFit.fill,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }
}
