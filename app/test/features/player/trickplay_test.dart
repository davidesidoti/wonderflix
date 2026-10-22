import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/trickplay.dart';

void main() {
  const info = TrickplayInfo(
    width: 320,
    height: 180,
    tileWidth: 10,
    tileHeight: 10,
    thumbnailCount: 700,
    interval: Duration(seconds: 10),
  );

  test('mosaico, colonna e riga per posizione', () {
    final first = trickplayTileAt(info, const Duration(minutes: 1))!;
    expect((first.sheet, first.column, first.row), (0, 6, 0));
    final hour = trickplayTileAt(info, const Duration(hours: 1))!;
    expect((hour.sheet, hour.column, hour.row), (3, 0, 6));
    final beyond = trickplayTileAt(info, const Duration(hours: 5))!;
    expect((beyond.sheet, beyond.column, beyond.row), (6, 9, 9),
        reason: 'oltre l\'ultima anteprima si usa l\'ultima');
    const empty = TrickplayInfo(
        width: 320,
        height: 180,
        tileWidth: 10,
        tileHeight: 10,
        thumbnailCount: 0,
        interval: Duration(seconds: 10));
    expect(trickplayTileAt(empty, Duration.zero), isNull);
    const noSize = TrickplayInfo(
        width: 0,
        height: 180,
        tileWidth: 10,
        tileHeight: 10,
        thumbnailCount: 100,
        interval: Duration(seconds: 10));
    expect(trickplayTileAt(noSize, Duration.zero), isNull);
  });

  test('URL del mosaico sotto il sotto-percorso del server', () {
    expect(
      trickplaySheetUrl(Uri.parse('https://host.example.com/jellyfin'),
          itemId: 'm1', width: 320, sheet: 3, mediaSourceId: 'ms1'),
      'https://host.example.com/jellyfin/Videos/m1/Trickplay/320/3.jpg?mediaSourceId=ms1',
    );
  });

  test('pickTrickplay: sorgente giusta e larghezza più vicina', () {
    Map<String, dynamic> width(int w) => {
          'Width': w,
          'Height': w * 9 ~/ 16,
          'TileWidth': 10,
          'TileHeight': 10,
          'ThumbnailCount': 100,
          'Interval': 10000,
        };
    final item = JellyfinItem.fromJson({
      'Id': 'm1',
      'Name': 'Dune',
      'Type': 'Movie',
      'Trickplay': {
        'ms1': {'160': width(160), '320': width(320), '640': width(640)},
        'ms2': {'480': width(480)},
      },
    });
    expect(pickTrickplay(item, 'ms1')?.info.width, 320);
    expect(pickTrickplay(item, 'ms1')?.mediaSourceId, 'ms1');
    expect(pickTrickplay(item, 'ms1', preferredWidth: 600)?.info.width, 640);
    expect(pickTrickplay(item, 'ms2')?.info.width, 480);
    expect(pickTrickplay(item, 'ms2')?.mediaSourceId, 'ms2');
    final fallback = pickTrickplay(item, 'altra');
    expect(fallback?.info.width, 320,
        reason: 'sorgente sconosciuta: la prima disponibile');
    expect(fallback?.mediaSourceId, 'ms1',
        reason: 'le anteprime vanno chieste per la loro sorgente');
    expect(
        pickTrickplay(
            JellyfinItem.fromJson({'Id': 'x', 'Name': 'x', 'Type': 'Movie'}),
            'ms1'),
        isNull);
  });
}
