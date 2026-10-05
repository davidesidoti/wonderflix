// Modelli delle richieste con Seerr (spec I §8.1), dalle risposte del plugin.

/// Film o serie, con i nomi di Seerr.
enum RequestMediaType {
  movie('movie'),
  tv('tv');

  const RequestMediaType(this.wire);

  /// Il nome nelle rotte dell'app e negli endpoint del plugin.
  final String wire;

  static RequestMediaType? tryParse(Object? raw) => switch (raw) {
        'movie' => movie,
        'tv' => tv,
        _ => null,
      };
}

/// Stato di un titolo o di una stagione (spec I §7.3).
enum TitleStatus {
  none,
  pending,
  processing,
  partial,
  available;

  static TitleStatus parse(Object? raw) => switch (raw) {
        'Pending' => pending,
        'Processing' => processing,
        'Partial' => partial,
        'Available' => available,
        _ => none,
      };

  /// Si può ancora chiedere: nessuno l'ha chiesto e non c'è.
  bool get isRequestable => this == none;
}

/// Stato di una richiesta (spec I §7.3). Uno sconosciuto vale "approvata".
enum RequestStatus {
  pending,
  approved,
  downloading,
  partial,
  available,
  declined,
  failed;

  static RequestStatus parse(Object? raw) => switch (raw) {
        'Pending' => pending,
        'Downloading' => downloading,
        'Partial' => partial,
        'Available' => available,
        'Declined' => declined,
        'Failed' => failed,
        _ => approved,
      };
}

/// Gli elenchi delle richieste (spec I §7.3).
enum RequestsFilter {
  mine('mine'),
  pending('pending'),
  all('all');

  const RequestsFilter(this.wire);

  final String wire;
}

/// Cosa può fare l'utente con Seerr (`GET Requests/Me`).
class RequestsMe {
  const RequestsMe({
    required this.canRequest,
    required this.canManage,
    required this.hasAccount,
  });

  factory RequestsMe.fromJson(Map<String, dynamic> json) => RequestsMe(
        canRequest: json['CanRequest'] == true,
        canManage: json['CanManage'] == true,
        hasAccount: json['HasAccount'] == true,
      );

  /// Funzione spenta o non ancora nota: niente pulsanti.
  static const none =
      RequestsMe(canRequest: false, canManage: false, hasAccount: false);

  final bool canRequest;

  /// Può approvare e rifiutare (piano 15b).
  final bool canManage;
  final bool hasAccount;
}

/// Un risultato della ricerca di Seerr (sezione "Da richiedere").
class RequestableTitle {
  const RequestableTitle({
    required this.mediaType,
    required this.tmdbId,
    required this.title,
    this.year,
    this.posterPath,
    this.status = TitleStatus.none,
    this.jellyfinItemId,
  });

  factory RequestableTitle.fromJson(Map<String, dynamic> json) =>
      RequestableTitle(
        mediaType: _mediaType(json['MediaType']),
        tmdbId: _int(json['TmdbId']),
        title: json['Title'] as String? ?? '',
        year: _intOrNull(json['Year']),
        posterPath: json['PosterPath'] as String?,
        status: TitleStatus.parse(json['Status']),
        jellyfinItemId: json['JellyfinItemId'] as String?,
      );

  final RequestMediaType mediaType;
  final int tmdbId;
  final String title;
  final int? year;

  /// Percorso TMDB ("/abc.jpg"), per [TmdbImages].
  final String? posterPath;
  final TitleStatus status;

  /// L'elemento della libreria, in formato "N" minuscolo, se Seerr lo conosce.
  final String? jellyfinItemId;
}

/// Una stagione di una serie, senza gli speciali.
class SeasonInfo {
  const SeasonInfo({
    required this.seasonNumber,
    required this.episodeCount,
    this.status = TitleStatus.none,
  });

  factory SeasonInfo.fromJson(Map<String, dynamic> json) => SeasonInfo(
        seasonNumber: _int(json['SeasonNumber']),
        episodeCount: _intOrNull(json['EpisodeCount']) ?? 0,
        status: TitleStatus.parse(json['Status']),
      );

  final int seasonNumber;
  final int episodeCount;
  final TitleStatus status;
}

/// La scheda di un titolo di Seerr (`GET Requests/Movie|Tv/{id}`).
class TitleDetails {
  const TitleDetails({
    required this.mediaType,
    required this.tmdbId,
    required this.title,
    this.year,
    this.overview,
    this.genres = const [],
    this.runtimeMinutes,
    this.posterPath,
    this.backdropPath,
    this.trailerUrl,
    this.status = TitleStatus.none,
    this.jellyfinItemId,
    this.requestedByMe = false,
    this.requested = false,
    this.seasons = const [],
  });

  factory TitleDetails.fromJson(Map<String, dynamic> json) => TitleDetails(
        mediaType: _mediaType(json['MediaType']),
        tmdbId: _int(json['TmdbId']),
        title: json['Title'] as String? ?? '',
        year: _intOrNull(json['Year']),
        overview: json['Overview'] as String?,
        genres: [
          for (final genre in json['Genres'] as List? ?? const []) genre as String,
        ],
        runtimeMinutes: _intOrNull(json['RuntimeMinutes']),
        posterPath: json['PosterPath'] as String?,
        backdropPath: json['BackdropPath'] as String?,
        trailerUrl: json['TrailerUrl'] as String?,
        status: TitleStatus.parse(json['Status']),
        jellyfinItemId: json['JellyfinItemId'] as String?,
        requestedByMe: json['RequestedByMe'] == true,
        requested: json['Requested'] == true,
        seasons: [
          for (final season in json['Seasons'] as List? ?? const [])
            SeasonInfo.fromJson(season as Map<String, dynamic>),
        ],
      );

  final RequestMediaType mediaType;
  final int tmdbId;
  final String title;
  final int? year;
  final String? overview;
  final List<String> genres;
  final int? runtimeMinutes;
  final String? posterPath;
  final String? backdropPath;

  /// Trailer su YouTube (http o https), già controllato dal plugin.
  final String? trailerUrl;
  final TitleStatus status;
  final String? jellyfinItemId;

  /// C'è una richiesta aperta dell'utente.
  final bool requestedByMe;

  /// C'è una richiesta aperta di qualcuno.
  final bool requested;

  /// Solo per le serie, senza gli speciali.
  final List<SeasonInfo> seasons;

  /// Le stagioni che si possono ancora chiedere.
  List<SeasonInfo> get requestableSeasons =>
      [for (final season in seasons) if (season.status.isRequestable) season];

  /// C'è qualcosa da chiedere: per un film lo stato, per una serie almeno
  /// una stagione.
  bool get canBeRequested => mediaType == RequestMediaType.movie
      ? status.isRequestable
      : requestableSeasons.isNotEmpty;
}

/// Risposta di `POST Requests`.
class CreatedRequest {
  const CreatedRequest({required this.id, required this.status});

  factory CreatedRequest.fromJson(Map<String, dynamic> json) => CreatedRequest(
      id: _int(json['Id']), status: RequestStatus.parse(json['Status']));

  final int id;

  /// `pending`, oppure un altro stato se Seerr l'ha approvata da sola.
  final RequestStatus status;
}

/// Chi ha chiesto un titolo.
class Requester {
  const Requester({required this.name, required this.isMe});

  factory Requester.fromJson(Map<String, dynamic> json) => Requester(
      name: json['Name'] as String? ?? '', isMe: json['IsMe'] == true);

  final String name;
  final bool isMe;
}

/// Una richiesta negli elenchi (piano 15b).
class MediaRequest {
  const MediaRequest({
    required this.id,
    required this.mediaType,
    required this.tmdbId,
    required this.title,
    required this.seasons,
    required this.requestedBy,
    required this.createdAt,
    required this.status,
    this.year,
    this.posterPath,
    this.progress,
    this.jellyfinItemId,
  });

  factory MediaRequest.fromJson(Map<String, dynamic> json) => MediaRequest(
        id: _int(json['Id']),
        mediaType: _mediaType(json['MediaType']),
        tmdbId: _int(json['TmdbId']),
        title: json['Title'] as String? ?? '',
        year: _intOrNull(json['Year']),
        posterPath: json['PosterPath'] as String?,
        seasons: [
          for (final season in json['Seasons'] as List? ?? const [])
            (season as num).toInt(),
        ],
        requestedBy: Requester.fromJson(
            json['RequestedBy'] as Map<String, dynamic>? ?? const {}),
        createdAt: DateTime.parse(json['CreatedAt'] as String),
        status: RequestStatus.parse(json['Status']),
        progress: (json['Progress'] as num?)?.toDouble(),
        jellyfinItemId: json['JellyfinItemId'] as String?,
      );

  final int id;
  final RequestMediaType mediaType;
  final int tmdbId;

  /// Vuoto se Seerr non l'ha dato.
  final String title;
  final int? year;
  final String? posterPath;
  final List<int> seasons;
  final Requester requestedBy;
  final DateTime createdAt;
  final RequestStatus status;

  /// Avanzamento del download, da 0 a 1.
  final double? progress;
  final String? jellyfinItemId;
}

/// Una pagina di richieste.
class RequestPage {
  const RequestPage({required this.items, required this.hasMore});

  factory RequestPage.fromJson(Map<String, dynamic> json) => RequestPage(
        items: [
          for (final item in json['Items'] as List? ?? const [])
            MediaRequest.fromJson(item as Map<String, dynamic>),
        ],
        hasMore: json['HasMore'] == true,
      );

  final List<MediaRequest> items;
  final bool hasMore;
}

/// Un profilo di qualità di Radarr o Sonarr.
class ProfileOption {
  const ProfileOption({required this.id, required this.name});

  factory ProfileOption.fromJson(Map<String, dynamic> json) => ProfileOption(
      id: _int(json['Id']), name: json['Name'] as String? ?? '');

  final int id;
  final String name;
}

/// Un server di Radarr o Sonarr per la finestra Approva (piano 15b).
class ServiceOption {
  const ServiceOption({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.profiles,
    required this.rootFolders,
    this.defaultProfileId,
    this.defaultRootFolder,
  });

  factory ServiceOption.fromJson(Map<String, dynamic> json) => ServiceOption(
        id: _int(json['Id']),
        name: json['Name'] as String? ?? '',
        isDefault: json['IsDefault'] == true,
        profiles: [
          for (final profile in json['Profiles'] as List? ?? const [])
            ProfileOption.fromJson(profile as Map<String, dynamic>),
        ],
        rootFolders: [
          for (final folder in json['RootFolders'] as List? ?? const [])
            folder as String,
        ],
        defaultProfileId: _intOrNull(json['DefaultProfileId']),
        defaultRootFolder: json['DefaultRootFolder'] as String?,
      );

  final int id;
  final String name;
  final bool isDefault;
  final List<ProfileOption> profiles;
  final List<String> rootFolders;
  final int? defaultProfileId;
  final String? defaultRootFolder;
}

/// Server, profilo e cartella scelti all'approvazione; tutto vuoto =
/// predefiniti di Seerr.
class ApproveChoice {
  const ApproveChoice({this.serverId, this.profileId, this.rootFolder});

  static const defaults = ApproveChoice();

  final int? serverId;
  final int? profileId;
  final String? rootFolder;

  Map<String, Object> toJson() => {
        'ServerId': ?serverId,
        'ProfileId': ?profileId,
        'RootFolder': ?rootFolder,
      };
}

RequestMediaType _mediaType(Object? raw) =>
    RequestMediaType.tryParse(raw) ?? (throw FormatException('MediaType: $raw'));

int _int(Object? raw) => (raw as num).toInt();

int? _intOrNull(Object? raw) => raw is num ? raw.toInt() : null;
