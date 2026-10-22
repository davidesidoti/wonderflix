/// I campi che Jellyfin sa bloccare uno per uno (`MetadataField`) fra quelli
/// dell'editor: gli altri si proteggono solo con "Blocca tutti i metadati".
const lockableFields = {'Name', 'Overview', 'Genres', 'OfficialRating'};

/// Una voce del menu delle classificazioni per età. [value] è `null` per
/// "nessuna".
class ParentalRatingOption {
  const ParentalRatingOption({required this.name, this.value});

  factory ParentalRatingOption.fromJson(Map<String, dynamic> json) =>
      ParentalRatingOption(
        name: json['Name'] as String,
        value: json['Value'] as int?,
      );

  final String name;
  final int? value;
}

/// Un risultato di "Identifica". [raw] è la `Map` ricevuta da Jellyfin: per
/// `Apply` si rimanda così com'è.
class RemoteSearchResult {
  const RemoteSearchResult({
    required this.raw,
    required this.name,
    this.year,
    this.imageUrl,
    this.provider,
    this.overview,
  });

  factory RemoteSearchResult.fromJson(Map<String, dynamic> json) =>
      RemoteSearchResult(
        raw: json,
        name: json['Name'] as String,
        year: json['ProductionYear'] as int?,
        imageUrl: json['ImageUrl'] as String?,
        provider: json['SearchProviderName'] as String?,
        overview: json['Overview'] as String?,
      );

  final Map<String, dynamic> raw;
  final String name;
  final int? year;
  final String? imageUrl;
  final String? provider;
  final String? overview;
}

/// I tipi di immagine che l'editor sa cambiare.
enum EditImageType {
  primary('Primary'),
  backdrop('Backdrop');

  const EditImageType(this.apiName);

  final String apiName;
}

/// Un'immagine proposta da un provider.
class RemoteImage {
  const RemoteImage({
    required this.url,
    required this.provider,
    this.thumbnailUrl,
    this.language,
    this.width,
    this.height,
    this.rating,
  });

  factory RemoteImage.fromJson(Map<String, dynamic> json) => RemoteImage(
        url: json['Url'] as String,
        provider: json['ProviderName'] as String,
        thumbnailUrl: json['ThumbnailUrl'] as String?,
        language: json['Language'] as String?,
        width: json['Width'] as int?,
        height: json['Height'] as int?,
        rating: (json['CommunityRating'] as num?)?.toDouble(),
      );

  final String url;
  final String provider;
  final String? thumbnailUrl;
  final String? language;
  final int? width;
  final int? height;
  final double? rating;
}

/// Una pagina di immagini; [total] è il numero di tutte quelle dei provider.
class RemoteImagesPage {
  const RemoteImagesPage({required this.images, required this.total});

  factory RemoteImagesPage.fromJson(Map<String, dynamic> json) =>
      RemoteImagesPage(
        images: [
          for (final raw in json['Images'] as List)
            RemoteImage.fromJson(raw as Map<String, dynamic>),
        ],
        total: json['TotalRecordCount'] as int,
      );

  final List<RemoteImage> images;
  final int total;
}
