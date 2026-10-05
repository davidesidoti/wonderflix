/// Modelli della libreria Jellyfin (sottoinsieme di `BaseItemDto`).
library;

enum ItemKind {
  movie('Movie'),
  series('Series'),
  season('Season'),
  episode('Episode'),
  person('Person'),
  other('');

  const ItemKind(this.apiName);

  /// Valore di `Type` / `includeItemTypes` nell'API.
  final String apiName;

  static ItemKind parse(String? value) {
    for (final kind in values) {
      if (kind != other && kind.apiName == value) return kind;
    }
    return other;
  }
}

/// 1 tick Jellyfin = 100 ns.
Duration ticksToDuration(int ticks) => Duration(microseconds: ticks ~/ 10);

/// Inverso di [ticksToDuration].
int durationToTicks(Duration duration) => duration.inMicroseconds * 10;

Map<String, String> _stringMap(Object? value) => value is Map
    ? {for (final e in value.entries) '${e.key}': '${e.value}'}
    : const {};

List<String> _stringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

List<Map<String, dynamic>> _objectList(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList()
    : const [];

int? _int(Object? value) => (value as num?)?.toInt();

int? _providerId(Object? raw, String key) {
  if (raw is! Map) return null;
  final value = raw[key];
  return value is String ? int.tryParse(value) : null;
}

double? _double(Object? value) => (value as num?)?.toDouble();

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// Stato dell'utente su un elemento: visto, preferito, minutaggio.
class UserItemData {
  const UserItemData({
    this.played = false,
    this.isFavorite = false,
    this.playbackPositionTicks = 0,
    this.playedPercentage,
    this.unplayedItemCount,
  });

  factory UserItemData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UserItemData();
    return UserItemData(
      played: json['Played'] as bool? ?? false,
      isFavorite: json['IsFavorite'] as bool? ?? false,
      playbackPositionTicks: _int(json['PlaybackPositionTicks']) ?? 0,
      playedPercentage: _double(json['PlayedPercentage']),
      unplayedItemCount: _int(json['UnplayedItemCount']),
    );
  }

  final bool played;
  final bool isFavorite;
  final int playbackPositionTicks;
  final double? playedPercentage;
  final int? unplayedItemCount;

  Duration get playbackPosition => ticksToDuration(playbackPositionTicks);

  /// Avanzamento 0–1; `null` se non iniziato o già visto.
  double? get progress {
    final percentage = playedPercentage;
    if (played || percentage == null || percentage <= 0) return null;
    return (percentage / 100).clamp(0.0, 1.0);
  }

  UserItemData copyWith({
    bool? played,
    bool? isFavorite,
    int? playbackPositionTicks,
    double? playedPercentage,
  }) =>
      UserItemData(
        played: played ?? this.played,
        isFavorite: isFavorite ?? this.isFavorite,
        playbackPositionTicks:
            playbackPositionTicks ?? this.playbackPositionTicks,
        playedPercentage: playedPercentage ?? this.playedPercentage,
        unplayedItemCount: unplayedItemCount,
      );
}

class PersonRef {
  const PersonRef({
    required this.id,
    required this.name,
    this.role,
    this.type,
    this.primaryImageTag,
  });

  factory PersonRef.fromJson(Map<String, dynamic> json) => PersonRef(
        id: json['Id'] as String,
        name: json['Name'] as String? ?? '',
        role: json['Role'] as String?,
        type: json['Type'] as String?,
        primaryImageTag: json['PrimaryImageTag'] as String?,
      );

  final String id;
  final String name;
  final String? role;
  final String? type;
  final String? primaryImageTag;
}

class TrailerLink {
  const TrailerLink({required this.url, this.name});

  factory TrailerLink.fromJson(Map<String, dynamic> json) =>
      TrailerLink(url: json['Url'] as String, name: json['Name'] as String?);

  final String url;
  final String? name;
}

/// Inizio di un capitolo del video.
class ChapterMark {
  const ChapterMark({required this.start, this.name});

  factory ChapterMark.fromJson(Map<String, dynamic> json) => ChapterMark(
        start: ticksToDuration(_int(json['StartPositionTicks']) ?? 0),
        name: json['Name'] as String?,
      );

  final Duration start;
  final String? name;
}

/// Mosaici di anteprime (trickplay) di una larghezza: ogni immagine
/// contiene [tileWidth] × [tileHeight] anteprime di [width] × [height] pixel,
/// una ogni [interval].
class TrickplayInfo {
  const TrickplayInfo({
    required this.width,
    required this.height,
    required this.tileWidth,
    required this.tileHeight,
    required this.thumbnailCount,
    required this.interval,
  });

  factory TrickplayInfo.fromJson(Map<String, dynamic> json) => TrickplayInfo(
        width: _int(json['Width']) ?? 0,
        height: _int(json['Height']) ?? 0,
        tileWidth: _int(json['TileWidth']) ?? 0,
        tileHeight: _int(json['TileHeight']) ?? 0,
        thumbnailCount: _int(json['ThumbnailCount']) ?? 0,
        interval: Duration(milliseconds: _int(json['Interval']) ?? 0),
      );

  final int width;
  final int height;
  final int tileWidth;
  final int tileHeight;
  final int thumbnailCount;
  final Duration interval;
}

/// `Trickplay` dell'API: sorgente → larghezza → informazioni.
Map<String, Map<int, TrickplayInfo>> _trickplay(Object? value) {
  final result = <String, Map<int, TrickplayInfo>>{};
  if (value is! Map) return result;
  for (final source in value.entries) {
    final widths = source.value;
    if (widths is! Map) continue;
    final byWidth = <int, TrickplayInfo>{};
    for (final entry in widths.entries) {
      final width = int.tryParse('${entry.key}');
      final info = entry.value;
      if (width != null && info is Map<String, dynamic>) {
        byWidth[width] = TrickplayInfo.fromJson(info);
      }
    }
    if (byWidth.isNotEmpty) result['${source.key}'] = byWidth;
  }
  return result;
}

class JellyfinItem {
  const JellyfinItem({
    required this.id,
    required this.name,
    required this.kind,
    this.overview,
    this.productionYear,
    this.officialRating,
    this.communityRating,
    this.runTimeTicks,
    this.genres = const [],
    this.sortName,
    this.dateCreated,
    this.imageTags = const {},
    this.backdropTags = const [],
    this.blurHashes = const {},
    this.seriesId,
    this.seriesName,
    this.seasonId,
    this.seriesPrimaryImageTag,
    this.parentBackdropItemId,
    this.parentBackdropTags = const [],
    this.parentLogoItemId,
    this.parentLogoImageTag,
    this.parentThumbItemId,
    this.parentThumbImageTag,
    this.indexNumber,
    this.parentIndexNumber,
    this.userData = const UserItemData(),
    this.people = const [],
    this.remoteTrailers = const [],
    this.localTrailerCount = 0,
    this.childCount,
    this.chapters = const [],
    this.trickplay = const {},
    this.tmdbId,
  });

  factory JellyfinItem.fromJson(Map<String, dynamic> json) {
    final hashes = <String, Map<String, String>>{};
    final rawHashes = json['ImageBlurHashes'];
    if (rawHashes is Map) {
      for (final entry in rawHashes.entries) {
        hashes['${entry.key}'] = _stringMap(entry.value);
      }
    }
    return JellyfinItem(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? '',
      kind: ItemKind.parse(json['Type'] as String?),
      overview: json['Overview'] as String?,
      productionYear: _int(json['ProductionYear']),
      officialRating: json['OfficialRating'] as String?,
      communityRating: _double(json['CommunityRating']),
      runTimeTicks: _int(json['RunTimeTicks']),
      genres: _stringList(json['Genres']),
      sortName: json['SortName'] as String?,
      dateCreated: _date(json['DateCreated']),
      imageTags: _stringMap(json['ImageTags']),
      backdropTags: _stringList(json['BackdropImageTags']),
      blurHashes: hashes,
      seriesId: json['SeriesId'] as String?,
      seriesName: json['SeriesName'] as String?,
      seasonId: json['SeasonId'] as String?,
      seriesPrimaryImageTag: json['SeriesPrimaryImageTag'] as String?,
      parentBackdropItemId: json['ParentBackdropItemId'] as String?,
      parentBackdropTags: _stringList(json['ParentBackdropImageTags']),
      parentLogoItemId: json['ParentLogoItemId'] as String?,
      parentLogoImageTag: json['ParentLogoImageTag'] as String?,
      parentThumbItemId: json['ParentThumbItemId'] as String?,
      parentThumbImageTag: json['ParentThumbImageTag'] as String?,
      indexNumber: _int(json['IndexNumber']),
      parentIndexNumber: _int(json['ParentIndexNumber']),
      userData: UserItemData.fromJson(json['UserData'] as Map<String, dynamic>?),
      people: _objectList(json['People']).map(PersonRef.fromJson).toList(),
      // `MediaUrl.Url` è nullable nell'API: scarta i trailer senza indirizzo.
      remoteTrailers: _objectList(json['RemoteTrailers'])
          .where((t) => t['Url'] is String && (t['Url'] as String).isNotEmpty)
          .map(TrailerLink.fromJson)
          .toList(),
      localTrailerCount: _int(json['LocalTrailerCount']) ?? 0,
      childCount: _int(json['ChildCount']),
      chapters: _objectList(json['Chapters']).map(ChapterMark.fromJson).toList(),
      trickplay: _trickplay(json['Trickplay']),
      tmdbId: _providerId(json['ProviderIds'], 'Tmdb'),
    );
  }

  final String id;
  final String name;
  final ItemKind kind;
  final String? overview;
  final int? productionYear;
  final String? officialRating;
  final double? communityRating;
  final int? runTimeTicks;
  final List<String> genres;

  /// Chiave d'ordinamento di Jellyfin (es. senza "The"). Arriva solo se
  /// chiesta (`ItemQuery.includeSortFields`).
  final String? sortName;

  /// Aggiunta alla libreria. Arriva solo se chiesta
  /// (`ItemQuery.includeSortFields`).
  final DateTime? dateCreated;

  /// Tipo immagine (`Primary`, `Logo`, `Thumb`…) → tag.
  final Map<String, String> imageTags;
  final List<String> backdropTags;

  /// Tipo immagine → (tag → blurhash).
  final Map<String, Map<String, String>> blurHashes;
  final String? seriesId;
  final String? seriesName;
  final String? seasonId;
  final String? seriesPrimaryImageTag;
  final String? parentBackdropItemId;
  final List<String> parentBackdropTags;
  final String? parentLogoItemId;
  final String? parentLogoImageTag;
  final String? parentThumbItemId;
  final String? parentThumbImageTag;
  final int? indexNumber;
  final int? parentIndexNumber;
  final UserItemData userData;
  final List<PersonRef> people;
  final List<TrailerLink> remoteTrailers;
  final int localTrailerCount;

  /// Per le serie: numero di stagioni.
  final int? childCount;

  /// Capitoli del video, in ordine.
  final List<ChapterMark> chapters;

  /// Anteprime per la barra di avanzamento: sorgente → larghezza → info.
  final Map<String, Map<int, TrickplayInfo>> trickplay;

  /// Id TMDB dell'elemento stesso, dai `ProviderIds`, se c'è (spec I §8.1):
  /// ha senso per film e serie, non è quello della serie di un episodio o di
  /// una stagione. Serve alle richieste con Seerr. `GET /Items/{id}` lo dà
  /// sempre; gli elenchi solo se chiesto (`ItemQuery.includeProviderIds`).
  final int? tmdbId;

  Duration? get runtime {
    final ticks = runTimeTicks;
    return ticks == null ? null : ticksToDuration(ticks);
  }
}

class ItemPage {
  const ItemPage(this.items, this.totalCount);

  final List<JellyfinItem> items;
  final int totalCount;
}

class LibraryFilters {
  const LibraryFilters({this.genres = const [], this.years = const []});

  final List<String> genres;

  /// Dal più recente al più vecchio.
  final List<int> years;
}
