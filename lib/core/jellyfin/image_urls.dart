import 'item_models.dart';

/// URL di un'immagine + blurhash per il segnaposto (se il server lo fornisce).
class ImageRef {
  const ImageRef(this.url, [this.blurHash]);

  final String url;
  final String? blurHash;
}

/// Costruisce gli URL delle immagini. Gli endpoint immagine di Jellyfin non
/// richiedono autenticazione, quindi nessun token finisce negli URL.
class ImageUrls {
  ImageUrls(Uri serverUrl) : _base = serverUrl.toString();

  final String _base;

  ImageRef _ref(
    JellyfinItem item,
    String ownerId,
    String type,
    String tag,
    int maxWidth, {
    int? index,
  }) {
    final path = index == null ? type : '$type/$index';
    return ImageRef(
      '$_base/Items/$ownerId/Images/$path?tag=$tag&maxWidth=$maxWidth&quality=90',
      item.blurHashes[type]?[tag],
    );
  }

  /// Locandina verticale 2:3. Per gli episodi usa quella della serie.
  ImageRef? poster(JellyfinItem item, {int maxWidth = 400}) {
    final seriesId = item.seriesId;
    final seriesTag = item.seriesPrimaryImageTag;
    if (item.kind == ItemKind.episode && seriesId != null && seriesTag != null) {
      return _ref(item, seriesId, 'Primary', seriesTag, maxWidth);
    }
    final tag = item.imageTags['Primary'];
    return tag == null ? null : _ref(item, item.id, 'Primary', tag, maxWidth);
  }

  /// Immagine principale di un elemento di cui si conosce solo l'id (es. la
  /// locandina di un invito nella cassetta, spec G §7.6): senza tag
  /// Jellyfin dà quella attuale.
  ImageRef primaryOf(String itemId, {int maxWidth = 120}) => ImageRef(
      '$_base/Items/$itemId/Images/Primary?maxWidth=$maxWidth&quality=90');

  /// Locandina di un elemento di cui si conoscono id e tag (una saga, spec K
  /// §8.4): con il tag l'immagine si rinnova quando cambia.
  ImageRef primaryWithTag(String itemId, String tag, {int maxWidth = 400}) =>
      ImageRef(
          '$_base/Items/$itemId/Images/Primary?tag=$tag&maxWidth=$maxWidth&quality=90');

  ImageRef? backdrop(JellyfinItem item, {int maxWidth = 1920}) {
    if (item.backdropTags.isNotEmpty) {
      return _ref(item, item.id, 'Backdrop', item.backdropTags.first, maxWidth,
          index: 0);
    }
    final parentId = item.parentBackdropItemId;
    if (parentId != null && item.parentBackdropTags.isNotEmpty) {
      return _ref(item, parentId, 'Backdrop', item.parentBackdropTags.first,
          maxWidth,
          index: 0);
    }
    return null;
  }

  ImageRef? logo(JellyfinItem item, {int maxWidth = 600}) {
    final tag = item.imageTags['Logo'];
    if (tag != null) return _ref(item, item.id, 'Logo', tag, maxWidth);
    final parentId = item.parentLogoItemId;
    final parentTag = item.parentLogoImageTag;
    if (parentId != null && parentTag != null) {
      return _ref(item, parentId, 'Logo', parentTag, maxWidth);
    }
    return null;
  }

  /// Immagine 16:9: fotogramma per gli episodi, altrimenti Thumb o sfondo.
  ImageRef? landscape(JellyfinItem item, {int maxWidth = 640}) {
    if (item.kind == ItemKind.episode) {
      final primary = item.imageTags['Primary'];
      if (primary != null) return _ref(item, item.id, 'Primary', primary, maxWidth);
    }
    final thumb = item.imageTags['Thumb'];
    if (thumb != null) return _ref(item, item.id, 'Thumb', thumb, maxWidth);
    final parentThumbId = item.parentThumbItemId;
    final parentThumb = item.parentThumbImageTag;
    if (parentThumbId != null && parentThumb != null) {
      return _ref(item, parentThumbId, 'Thumb', parentThumb, maxWidth);
    }
    return backdrop(item, maxWidth: maxWidth);
  }

  ImageRef? person(PersonRef person, {int maxWidth = 240}) {
    final tag = person.primaryImageTag;
    if (tag == null) return null;
    return ImageRef(
        '$_base/Items/${person.id}/Images/Primary?tag=$tag&maxWidth=$maxWidth&quality=90');
  }
}
