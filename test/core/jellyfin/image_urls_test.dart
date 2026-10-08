import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/image_urls.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';

void main() {
  final urls = ImageUrls(Uri.parse('https://media.example.com/jf'));

  const movie = JellyfinItem(
    id: 'm1',
    name: 'Dune',
    kind: ItemKind.movie,
    imageTags: {'Primary': 'p1', 'Logo': 'l1', 'Thumb': 't1'},
    backdropTags: ['b1'],
    blurHashes: {
      'Primary': {'p1': 'HASH'},
    },
  );

  const episode = JellyfinItem(
    id: 'e1',
    name: 'Ep',
    kind: ItemKind.episode,
    imageTags: {'Primary': 'ep1'},
    seriesId: 's1',
    seriesPrimaryImageTag: 'sp1',
    parentBackdropItemId: 's1',
    parentBackdropTags: ['sb1'],
    parentLogoItemId: 's1',
    parentLogoImageTag: 'sl1',
  );

  test('poster del film con blurhash', () {
    final ref = urls.poster(movie)!;
    expect(ref.url,
        'https://media.example.com/jf/Items/m1/Images/Primary?tag=p1&maxWidth=400&quality=90');
    expect(ref.blurHash, 'HASH');
  });

  test('il poster di un episodio è quello della serie', () {
    expect(urls.poster(episode)!.url, contains('/Items/s1/Images/Primary?tag=sp1'));
  });

  test('sfondo proprio o del genitore', () {
    expect(urls.backdrop(movie)!.url, contains('/Items/m1/Images/Backdrop/0?tag=b1'));
    expect(urls.backdrop(episode)!.url, contains('/Items/s1/Images/Backdrop/0?tag=sb1'));
  });

  test('logo proprio o del genitore', () {
    expect(urls.logo(movie)!.url, contains('/Items/m1/Images/Logo?tag=l1'));
    expect(urls.logo(episode)!.url, contains('/Items/s1/Images/Logo?tag=sl1'));
  });

  test('immagine orizzontale: fotogramma per episodi, Thumb per i film', () {
    expect(urls.landscape(episode)!.url, contains('/Items/e1/Images/Primary?tag=ep1'));
    expect(urls.landscape(movie)!.url, contains('/Items/m1/Images/Thumb?tag=t1'));
  });

  test('senza immagini restituisce null', () {
    const bare = JellyfinItem(id: 'x', name: 'x', kind: ItemKind.movie);
    expect(urls.poster(bare), isNull);
    expect(urls.backdrop(bare), isNull);
    expect(urls.landscape(bare), isNull);
  });

  test('foto di una persona', () {
    const person = PersonRef(id: 'p9', name: 'Zendaya', primaryImageTag: 'pp9');
    expect(urls.person(person)!.url,
        'https://media.example.com/jf/Items/p9/Images/Primary?tag=pp9&maxWidth=240&quality=90');
    expect(urls.person(const PersonRef(id: 'p0', name: 'X')), isNull);
  });

  test('immagine principale da un id, senza tag', () {
    final image = urls.primaryOf('m1');
    expect(image.url,
        'https://media.example.com/jf/Items/m1/Images/Primary?maxWidth=120&quality=90');
    expect(image.blurHash, isNull);
    expect(urls.primaryOf('m1', maxWidth: 300).url, contains('maxWidth=300'));
  });

  test('locandina da id e tag (una saga, spec K §8.4)', () {
    final image = urls.primaryWithTag('c1', 't1');
    expect(image.url,
        'https://media.example.com/jf/Items/c1/Images/Primary?tag=t1&maxWidth=400&quality=90');
    expect(urls.primaryWithTag('c1', 't1', maxWidth: 300).url, contains('maxWidth=300'));
  });

  test('immagine di un utente: con il tag, senza ridimensionare', () {
    expect(urls.user('u1', 't1').url,
        'https://media.example.com/jf/UserImage?userId=u1&tag=t1');
  });
}
