import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_edit_models.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/item_edit/images_dialog.dart';
import 'package:wonderflix/features/item_edit/item_edit_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/item_edit_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

RemoteImage _image(int n, {String? language = 'it'}) => RemoteImage(
      url: 'https://img.example.com/$n.jpg',
      provider: 'TheMovieDb',
      thumbnailUrl: 'https://img.example.com/t$n.jpg',
      width: 1000 + n,
      height: 1500,
      language: language,
      rating: 5.3,
    );

/// Il download passa, la rilettura degli sfondi no.
class _RawFails extends FakeItemEditApi {
  @override
  Future<Map<String, dynamic>> rawItem(String userId, String itemId) async {
    calls.add('rawItem $itemId');
    throw const ServerUnreachableException();
  }
}

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  late FakeItemEditApi api;
  late FakeLibraryApi library;
  late FakeSessionController session;
  PickedImageFile? picked;

  setUp(() {
    api = FakeItemEditApi()
      ..items['i1'] = testRawItem(backdropImageTags: ['b1', 'b2', 'b3'])
      ..items['one'] = testRawItem(id: 'one', backdropImageTags: ['b1'])
      ..page = RemoteImagesPage(images: [_image(1), _image(2)], total: 2);
    library = FakeLibraryApi()
      ..itemsById['i1'] = testItem(id: 'i1', kind: ItemKind.series)
      ..itemsById['one'] = testItem(id: 'one', kind: ItemKind.series)
      ..itemsById['se1'] = testItem(id: 'se1', kind: ItemKind.season)
      ..itemsById['bare'] = JellyfinItem.fromJson(
          {'Id': 'bare', 'Name': 'Senza', 'Type': 'Series'});
    session = FakeSessionController(const SessionSignedIn(testAdmin));
    picked = null;
  });

  Future<void> open(
    WidgetTester tester, {
    String id = 'i1',
    ItemKind kind = ItemKind.series,
    Size surfaceSize = const Size(1440, 900),
  }) async {
    await pumpApp(
      tester,
      surfaceSize: surfaceSize,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                unawaited(showImagesDialog(context, itemId: id, kind: kind)),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: [
        itemEditApiProvider.overrideWithValue(api),
        libraryApiProvider.overrideWithValue(library),
        imageFilePickerProvider.overrideWithValue((_) async => picked),
        sessionControllerProvider.overrideWith(() => session),
      ],
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  int revision(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
          .read(libraryRevisionProvider);

  Future<void> openBackdropTab(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ChoiceChip, it.imagesBackdrop));
    await tester.pumpAndSettle();
  }

  PickedImageFile file(String name, int length, {int? bytes}) =>
      PickedImageFile(
        name: name,
        length: length,
        read: () async => Uint8List(bytes ?? length),
      );

  test('imageTabsFor per i quattro livelli', () {
    const both = [EditImageType.primary, EditImageType.backdrop];
    expect(imageTabsFor(ItemKind.movie), both);
    expect(imageTabsFor(ItemKind.series), both);
    expect(imageTabsFor(ItemKind.season), [EditImageType.primary]);
    expect(imageTabsFor(ItemKind.episode), [EditImageType.primary]);
  });

  test('backdropToMoveFirst', () {
    expect(backdropToMoveFirst(0), isNull);
    expect(backdropToMoveFirst(1), isNull);
    expect(backdropToMoveFirst(2), 1);
    expect(backdropToMoveFirst(5), 4);
  });

  testWidgets('una sola scheda per stagioni ed episodi: niente riga',
      (tester) async {
    await open(tester, id: 'se1', kind: ItemKind.season);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(api.calls, ['remoteImages se1 Primary 0 false']);
  });

  testWidgets('immagine attuale o "nessuna immagine"', (tester) async {
    await open(tester);
    expect(find.text(it.imagesCurrent), findsOneWidget);
    expect(find.text(it.imagesNone), findsNothing);
    await tester.tap(find.text(it.imagesBackdrop));
    await tester.pumpAndSettle();
    expect(find.text(it.imagesNone), findsNothing);
  });

  testWidgets('senza immagine attuale compare "nessuna immagine"',
      (tester) async {
    await open(tester, id: 'bare');
    expect(find.text(it.imagesNone), findsOneWidget);
  });

  testWidgets('griglia, tutte le lingue, altre immagini', (tester) async {
    api.page = RemoteImagesPage(images: [_image(1), _image(2)], total: 3);
    await open(tester);

    expect(find.text(it.imagesUse), findsNWidgets(2));
    expect(find.text('TheMovieDb · 1001×1500 · it · 5.3'), findsOneWidget);

    // Tutte le lingue rilegge da capo.
    await tester.tap(find.text(it.imagesAllLanguages));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'remoteImages i1 Primary 0 true');
    expect(find.text(it.imagesUse), findsNWidgets(2));

    // Altre immagini aggiunge la pagina successiva e poi sparisce.
    api.page = RemoteImagesPage(images: [_image(3)], total: 3);
    await tester.tap(find.text(it.imagesMore));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'remoteImages i1 Primary 2 true');
    expect(find.text(it.imagesUse), findsNWidgets(3));
    expect(find.text(it.imagesMore), findsNothing);
  });

  testWidgets('nessuna immagine dai provider', (tester) async {
    api.page = const RemoteImagesPage(images: [], total: 0);
    await open(tester);
    expect(find.text(it.imagesNoResults), findsOneWidget);
    expect(find.text(it.imagesMore), findsNothing);
  });

  testWidgets('Usa come locandina: download e bump', (tester) async {
    await open(tester);
    final before = revision(tester);

    await tester.tap(find.text(it.imagesUse).first);
    await tester.pumpAndSettle();

    expect(api.calls, [
      'remoteImages i1 Primary 0 false',
      'downloadImage i1 Primary https://img.example.com/1.jpg',
    ]);
    expect(revision(tester), before + 1);
    expect(find.text(it.imagesSaved), findsOneWidget);
    expect(find.text(it.imagesTitle), findsOneWidget);
  });

  testWidgets('Usa come sfondo: download, rilettura e spostamento '
      'dell\'ultimo a 0', (tester) async {
    await open(tester);
    await openBackdropTab(tester);
    final before = revision(tester);

    await tester.tap(find.text(it.imagesUse).first);
    await tester.pumpAndSettle();

    expect(api.calls, [
      'remoteImages i1 Primary 0 false',
      'remoteImages i1 Backdrop 0 false',
      'downloadImage i1 Backdrop https://img.example.com/1.jpg',
      'rawItem i1',
      'moveBackdropFirst i1 2',
    ]);
    expect(revision(tester), before + 1);
    expect(find.text(it.imagesSaved), findsOneWidget);
  });

  testWidgets('un solo sfondo: niente spostamento', (tester) async {
    await open(tester, id: 'one');
    await openBackdropTab(tester);

    await tester.tap(find.text(it.imagesUse).first);
    await tester.pumpAndSettle();

    expect(api.calls.last, 'rawItem one');
    expect(api.calls.where((c) => c.startsWith('moveBackdropFirst')), isEmpty);
  });

  testWidgets('lo spostamento che fallisce: errore, ma la scheda si rilegge',
      (tester) async {
    api = _RawFails()
      ..items['i1'] = testRawItem(backdropImageTags: ['b1', 'b2'])
      ..page = RemoteImagesPage(images: [_image(1)], total: 1);
    await open(tester);
    await openBackdropTab(tester);
    final before = revision(tester);

    await tester.tap(find.text(it.imagesUse).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('non è raggiungibile'), findsOneWidget);
    expect(find.text(it.imagesSaved), findsNothing);
    // Il download è andato a buon fine: la scheda mostra comunque la novità.
    expect(revision(tester), before + 1);
  });

  testWidgets('file oltre 10 MB: messaggio e nessuna chiamata', (tester) async {
    await open(tester);
    final before = revision(tester);
    picked = PickedImageFile(
      name: 'grande.png',
      length: maxImageFileBytes + 1,
      read: () => throw StateError('non va letto'),
    );

    await tester.tap(find.text(it.imagesUpload));
    await tester.pumpAndSettle();

    expect(find.text(it.imagesFileTooLarge), findsOneWidget);
    expect(api.calls, ['remoteImages i1 Primary 0 false']);
    expect(revision(tester), before);
  });

  testWidgets('upload png con il content type giusto', (tester) async {
    await open(tester);
    final before = revision(tester);
    picked = file('Locandina.PNG', 4);

    await tester.tap(find.text(it.imagesUpload));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'uploadImage i1 Primary 4 image/png');
    expect(revision(tester), before + 1);
    expect(find.text(it.imagesSaved), findsOneWidget);

    picked = file('foto.jpg', 6);
    await tester.tap(find.text(it.imagesUpload));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'uploadImage i1 Primary 6 image/jpeg');
  });

  testWidgets('upload di uno sfondo: sposta il nuovo in prima posizione',
      (tester) async {
    await open(tester);
    await openBackdropTab(tester);
    picked = file('s.jpg', 3);

    await tester.tap(find.text(it.imagesUpload));
    await tester.pumpAndSettle();

    expect(api.calls.sublist(api.calls.length - 3), [
      'uploadImage i1 Backdrop 3 image/jpeg',
      'rawItem i1',
      'moveBackdropFirst i1 2',
    ]);
  });

  testWidgets('scelta annullata: nessuna chiamata', (tester) async {
    await open(tester);
    await tester.tap(find.text(it.imagesUpload));
    await tester.pumpAndSettle();
    expect(api.calls, ['remoteImages i1 Primary 0 false']);
    expect(find.text(it.imagesSaved), findsNothing);
  });

  testWidgets('doppio clic: una sola chiamata', (tester) async {
    await open(tester);
    final gate = api.gate = Completer<void>();

    await tester.tap(find.text(it.imagesUse).first);
    await tester.pump();
    await tester.tap(find.text(it.imagesUse).first, warnIfMissed: false);
    await tester.tap(find.text(it.imagesUpload), warnIfMissed: false);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => c.startsWith('downloadImage')).length, 1);
    expect(api.calls.where((c) => c.startsWith('uploadImage')), isEmpty);
  });

  testWidgets('un 403 rilegge l\'utente; niente bump', (tester) async {
    await open(tester);
    final before = revision(tester);
    api.nextFailure = const ForbiddenException();

    await tester.tap(find.text(it.imagesUse).first);
    await tester.pumpAndSettle();

    expect(find.text(it.editNoPermission), findsOneWidget);
    expect(session.refreshUserCalls, 1);
    expect(revision(tester), before);
    expect(find.text(it.imagesSaved), findsNothing);
  });

  testWidgets('un altro errore resta nella finestra', (tester) async {
    await open(tester);
    api.nextFailure = const ServerUnreachableException();

    await tester.tap(find.text(it.imagesUse).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('non è raggiungibile'), findsOneWidget);
    expect(session.refreshUserCalls, 0);
  });

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    testWidgets('telefono ${size.width.toInt()}x${size.height.toInt()}: nessun overflow', (tester) async {
      await open(tester, surfaceSize: size);
      expect(tester.takeException(), isNull);
    });
  }
}
