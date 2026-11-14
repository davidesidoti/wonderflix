import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/genre_labels.dart';

void main() {
  test('i nomi inglesi diventano italiani, gli altri restano', () {
    expect(genreLabel('Drama'), 'Dramma');
    expect(genreLabel('Science Fiction'), 'Fantascienza');
    expect(genreLabel('Sci-Fi'), 'Fantascienza');
    expect(genreLabel('Suspense'), 'Thriller');
    expect(genreLabel('Anime'), 'Anime');
    expect(genreLabel('Dramma'), 'Dramma');
  });

  test('un\'etichetta torna a tutti i suoi nomi del server', () {
    expect(genreServerNames('Dramma'), ['Dramma', 'Drama']);
    expect(genreServerNames('Fantascienza'),
        ['Fantascienza', 'Sci-Fi', 'Science Fiction']);
    expect(genreServerNames('Anime'), ['Anime']);
  });
}
