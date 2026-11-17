/// Nome inglese del server -> etichetta italiana (spec §6.2).
const _labels = {
  'Drama': 'Dramma',
  'Action': 'Azione',
  'Adventure': 'Avventura',
  'Science Fiction': 'Fantascienza',
  'Sci-Fi': 'Fantascienza',
  'Comedy': 'Commedia',
  'Mystery': 'Mistero',
  'Animation': 'Animazione',
  'Documentary': 'Documentario',
  'History': 'Storia',
  'War': 'Guerra',
  'Family': 'Famiglia',
  'Sport': 'Sport',
  'Sports': 'Sport',
  'Suspense': 'Thriller',
  'Mini-Series': 'Miniserie',
  'Music': 'Musica',
  'Supernatural': 'Soprannaturale',
  'Crime': 'Poliziesco',
  'Romance': 'Romantico',
  'Psychological': 'Psicologico',
  'Martial Arts': 'Arti marziali',
  'Medical': 'Medico',
  'Food': 'Cucina',
  'televisione film': 'Film TV',
  // Generi TV di TMDB, che Seerr dà in inglese anche con language=it.
  'Action & Adventure': 'Azione e avventura',
  'Sci-Fi & Fantasy': 'Fantascienza e fantasy',
  'War & Politics': 'Guerra e politica',
  'Kids': 'Bambini',
  'Talk': 'Talk show',
  'News': 'Notizie',
};

/// Etichetta italiana di un genere del server; quelli senza voce restano uguali.
String genreLabel(String serverName) => _labels[serverName] ?? serverName;

/// Al massimo [max] generi tradotti e senza doppioni.
List<String> displayGenres(List<String> genres, {int max = 2}) =>
    <String>{...genres.map(genreLabel)}.take(max).toList();

/// Tutti i nomi del server che portano a [label]: l'etichetta per prima (può
/// essere un genere già italiano), poi i nomi inglesi in ordine alfabetico.
List<String> genreServerNames(String label) => [
      label,
      ...(_labels.entries
          .where((e) => e.value == label && e.key != label)
          .map((e) => e.key)
          .toList()
        ..sort()),
    ];
