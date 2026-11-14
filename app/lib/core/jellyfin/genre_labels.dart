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
};

/// Etichetta italiana di un genere del server; quelli senza voce restano uguali.
String genreLabel(String serverName) => _labels[serverName] ?? serverName;

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
