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

  test('i generi del server senza traduzione diventano italiani', () {
    expect(genreLabel('Crime'), 'Poliziesco');
    expect(genreLabel('Romance'), 'Romantico');
    expect(genreLabel('Psychological'), 'Psicologico');
    expect(genreLabel('Martial Arts'), 'Arti marziali');
    expect(genreLabel('Medical'), 'Medico');
    expect(genreLabel('Food'), 'Cucina');
    expect(genreLabel('televisione film'), 'Film TV');
    expect(genreLabel('Fantasy'), 'Fantasy');
  });

  test('Poliziesco manda al server anche Crime', () {
    expect(genreServerNames('Poliziesco'), ['Poliziesco', 'Crime']);
  });
}
