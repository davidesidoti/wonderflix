import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/profiles/avatar_cropper.dart';
import 'package:wonderflix/features/profiles/avatar_dialog.dart';
import 'package:wonderflix/features/profiles/avatar_gallery.dart';
import 'package:wonderflix/features/profiles/avatar_image.dart';
import 'package:wonderflix/features/social/avatars_provider.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/avatar_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

/// Il lavoro sulle immagini, senza isolate né `toImage`.
class _FakeTools extends AvatarImageTools {
  Object? prepareError;
  final prepared = <Uint8List>[];
  final cropped = <CropArea>[];

  @override
  Future<Uint8List> renderGallery(GalleryAvatar avatar) async =>
      Uint8List.fromList([7]);

  @override
  Future<WorkingImage> prepare(Uint8List bytes) async {
    prepared.add(bytes);
    final error = prepareError;
    if (error != null) throw error;
    return WorkingImage(
        img.encodePng(img.Image(width: 4, height: 2)), 400, 200);
  }

  @override
  Future<Uint8List> crop(WorkingImage image, CropArea area) async {
    cropped.add(area);
    return Uint8List.fromList([8]);
  }
}

void main() {
  late FakeSessionController session;
  late _FakeTools tools;
  PickedAvatarFile? picked;

  setUp(() {
    session = FakeSessionController(const SessionSignedIn(testUser));
    tools = _FakeTools();
    picked = null;
  });

  List<Override> dialogOverrides() => [
        sessionControllerProvider.overrideWith(() => session),
        avatarImageToolsProvider.overrideWithValue(tools),
        avatarFilePickerProvider.overrideWithValue((label) async => picked),
      ];

  /// Il pulsante che apre la finestra, con [below] sotto.
  Widget opener({String? imageTag, Widget? below}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(showAvatarDialog(context,
                  userId: 'u1', name: 'Mario', imageTag: imageTag)),
              child: const Text('apri'),
            ),
          ),
          ?below,
        ],
      );

  Future<void> openDialog(WidgetTester tester,
      {String? imageTag,
      Widget? below,
      List<Override> overrides = const [],
      Size surfaceSize = const Size(1440, 900)}) async {
    await pumpApp(
      tester,
      opener(imageTag: imageTag, below: below),
      surfaceSize: surfaceSize,
      overrides: [...dialogOverrides(), ...overrides],
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  VoidCallback? onPressed(WidgetTester tester, String label) =>
      tester.widget<WfButton>(find.widgetWithText(WfButton, label)).onPressed;

  Future<void> chooseGalleryAvatar(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('gallery-3')));
    await tester.pump();
    await tester.tap(find.text('Usa questo'));
    await tester.pump();
  }

  testWidgets('tre schede; "Usa questo" solo con un avatar scelto',
      (tester) async {
    await openDialog(tester);

    expect(find.text('Immagine del profilo'), findsOneWidget);
    expect(find.text('Avatar'), findsOneWidget);
    expect(find.text('Dal PC'), findsOneWidget);
    expect(find.text('Rimuovi'), findsOneWidget);
    expect(onPressed(tester, 'Usa questo'), isNull);

    await tester.tap(find.byKey(const ValueKey('gallery-3')));
    await tester.pump();
    expect(onPressed(tester, 'Usa questo'), isNotNull);
  });

  testWidgets('un avatar della galleria: un PNG, poi la finestra si chiude',
      (tester) async {
    await openDialog(tester);

    await chooseGalleryAvatar(tester);
    await tester.pumpAndSettle();

    final (userId, upload) = session.profileImageCalls.single;
    expect(userId, 'u1');
    expect(upload!.contentType, 'image/png');
    expect(upload.bytes, [7]);
    expect(find.text('Immagine del profilo'), findsNothing);
  });

  testWidgets('senza permesso: il messaggio, e la finestra resta',
      (tester) async {
    await openDialog(tester);
    session.profileImageError = const ForbiddenException();

    await chooseGalleryAvatar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Non hai il permesso di cambiare l\'immagine'),
        findsOneWidget);
    expect(find.text('Immagine del profilo'), findsOneWidget);
  });

  testWidgets('un altro errore: "Caricamento non riuscito"', (tester) async {
    await openDialog(tester);
    session.profileImageError = const ServerErrorException(500);

    await chooseGalleryAvatar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Caricamento non riuscito'), findsOneWidget);
  });

  testWidgets('un 401: il profilo è scaduto e la finestra si chiude',
      (tester) async {
    await openDialog(tester);
    session.profileImageError = const UnauthorizedException();

    await chooseGalleryAvatar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Immagine del profilo'), findsNothing);
  });

  testWidgets('cambiando scheda il messaggio d\'errore sparisce',
      (tester) async {
    await openDialog(tester);
    session.profileImageError = const ForbiddenException();
    await chooseGalleryAvatar(tester);
    await tester.pumpAndSettle();
    expect(find.text('Non hai il permesso di cambiare l\'immagine'),
        findsOneWidget);

    await tester.tap(find.text('Dal PC'));
    await tester.pumpAndSettle();

    expect(find.text('Non hai il permesso di cambiare l\'immagine'),
        findsNothing);
  });

  testWidgets('finestra più piccola, con l\'errore: le 4 righe della '
      'galleria ci stanno, gli avatar hanno il loro lato', (tester) async {
    // 1024×640 fuori, circa 1008×600 dentro: un'altezza che sbordasse
    // farebbe fallire il test.
    await openDialog(tester, surfaceSize: const Size(1008, 600));
    session.profileImageError = const ServerErrorException(500);

    await chooseGalleryAvatar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Caricamento non riuscito'), findsOneWidget);
    final last = find.byKey(ValueKey('gallery-${galleryAvatars.length - 1}'));
    expect(tester.getRect(last).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(GridView)).bottom));
    expect(tester.getSize(find.byType(GalleryAvatarView).first),
        const Size(56, 56));
  });

  testWidgets('gli avatar della galleria: pulsanti con un nome, e quale è '
      'scelto', (tester) async {
    final semantics = tester.ensureSemantics();
    await openDialog(tester);
    final tile = find.byKey(const ValueKey('gallery-3'));
    expect(tester.getSemantics(tile),
        isSemantics(label: 'Avatar 4', isButton: true, isSelected: false));

    await tester.tap(tile);
    await tester.pump();

    expect(tester.getSemantics(tile),
        isSemantics(label: 'Avatar 4', isButton: true, isSelected: true));
    semantics.dispose();
  });

  testWidgets('durante il caricamento i pulsanti sono spenti', (tester) async {
    await openDialog(tester);
    final gate = Completer<void>();
    session.profileImageGate = gate;
    final top = tester.getTopLeft(find.byType(TabBarView));

    await chooseGalleryAvatar(tester);

    expect(onPressed(tester, 'Usa questo'), isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // L'indicatore ha già il suo spazio: il contenuto non si sposta.
    expect(tester.getTopLeft(find.byType(TabBarView)), top);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Immagine del profilo'), findsNothing);
  });

  testWidgets('durante il caricamento Esc e il clic fuori non la chiudono',
      (tester) async {
    await openDialog(tester);
    final gate = Completer<void>();
    session.profileImageGate = gate;
    await chooseGalleryAvatar(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.text('Immagine del profilo'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Immagine del profilo'), findsNothing);
    expect(find.text('apri'), findsOneWidget);
  });

  testWidgets('un caricamento che finisce a finestra chiusa non chiude la '
      'pagina sotto', (tester) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => unawaited(Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => Scaffold(body: Center(child: opener()))))),
          child: const Text('pagina'),
        ),
      ),
      overrides: dialogOverrides(),
    );
    await tester.tap(find.text('pagina'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    session.profileImageGate = gate;
    await chooseGalleryAvatar(tester);

    // Qualcos'altro chiude la finestra (per esempio la sessione che
    // cambia); il caricamento finisce mentre si chiude.
    Navigator.of(tester.element(find.byType(AvatarDialog))).pop();
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Immagine del profilo'), findsNothing);
    expect(find.text('apri'), findsOneWidget);
  });

  testWidgets('Dal PC: annullato, troppo grande, non valido', (tester) async {
    await openDialog(tester);
    await tester.tap(find.text('Dal PC'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scegli un\'immagine…'));
    await tester.pumpAndSettle();
    expect(tools.prepared, isEmpty);

    picked = PickedAvatarFile(
        length: maxAvatarFileBytes + 1, read: () async => Uint8List(0));
    await tester.tap(find.text('Scegli un\'immagine…'));
    await tester.pumpAndSettle();
    expect(find.text('Immagine troppo grande'), findsOneWidget);
    expect(tools.prepared, isEmpty);

    picked = PickedAvatarFile(
        length: 3, read: () async => Uint8List.fromList([1, 2, 3]));
    tools.prepareError = const AvatarImageException(AvatarImageError.invalid);
    await tester.tap(find.text('Scegli un\'immagine…'));
    await tester.pumpAndSettle();
    expect(find.text('Immagine non valida'), findsOneWidget);
  });

  testWidgets('Dal PC: il ritaglio, poi un JPEG', (tester) async {
    picked = PickedAvatarFile(
        length: 3, read: () async => Uint8List.fromList([1, 2, 3]));
    await openDialog(tester);
    await tester.tap(find.text('Dal PC'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scegli un\'immagine…'));
    await tester.pumpAndSettle();
    expect(find.byType(AvatarCropper), findsOneWidget);

    await tester.tap(find.text('Usa questa'));
    await tester.pumpAndSettle();

    // L'immagine di lavoro (400×200) centrata e intera in altezza.
    expect(tools.cropped.single, const CropArea(100, 0, 200));
    final (_, upload) = session.profileImageCalls.single;
    expect(upload!.contentType, 'image/jpeg');
    expect(upload.bytes, [8]);
  });

  testWidgets('Dal PC: cambiando scheda il ritaglio resta quello che si vede',
      (tester) async {
    picked = PickedAvatarFile(
        length: 3, read: () async => Uint8List.fromList([1, 2, 3]));
    await openDialog(tester);
    await tester.tap(find.text('Dal PC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scegli un\'immagine…'));
    await tester.pumpAndSettle();
    // Il cursore in fondo: 4×.
    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Avatar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dal PC'));
    await tester.pumpAndSettle();

    expect(tester.widget<Slider>(find.byType(Slider)).value, maxCropZoom);
    await tester.tap(find.text('Usa questa'));
    await tester.pumpAndSettle();
    // Riquadro di 240 sull'immagine 400×200 a 4×, centrata: un quadrato di
    // 50 px al centro.
    expect(tools.cropped.single, const CropArea(175, 75, 50));
  });

  testWidgets('Dal PC: trascinare l\'immagine non cambia scheda',
      (tester) async {
    picked = PickedAvatarFile(
        length: 3, read: () async => Uint8List.fromList([1, 2, 3]));
    await openDialog(tester);
    await tester.tap(find.text('Dal PC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scegli un\'immagine…'));
    await tester.pumpAndSettle();

    await tester.drag(
        find.byKey(const Key('avatar-crop-area')), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.byType(AvatarCropper), findsOneWidget);
    expect(find.text('Usa questa'), findsOneWidget);
  });

  testWidgets('Rimuovi: spento senza immagine', (tester) async {
    await openDialog(tester);
    await tester.tap(find.text('Rimuovi'));
    await tester.pumpAndSettle();

    expect(onPressed(tester, 'Rimuovi immagine'), isNull);
  });

  testWidgets('Rimuovi: con un\'immagine la toglie', (tester) async {
    await openDialog(tester, imageTag: 't1');
    await tester.tap(find.text('Rimuovi'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rimuovi immagine'));
    await tester.pumpAndSettle();

    expect(session.profileImageCalls.single, ('u1', null));
  });

  testWidgets('dopo il caricamento la cache degli avatar ha l\'immagine nuova, '
      'e gli avatar sullo schermo la mostrano', (tester) async {
    final api = FakeAvatarsApi();
    // Gli avatar dell'utente già sullo schermo, per id e per nome.
    final onScreen = Consumer(builder: (context, ref, _) {
      final byId = ref.watch(avatarImageProvider(AvatarLookup.byId('u1')));
      final byName =
          ref.watch(avatarImageProvider(AvatarLookup.byName('Mario')));
      return Text('id ${byId.value?.tag} nome ${byName.value?.tag}');
    });
    await openDialog(tester, below: onScreen, overrides: [
      // Con `overrideWith` la cache si chiude con il container: nessun timer
      // resta in sospeso a fine test.
      avatarDirectoryProvider.overrideWith((ref) {
        final directory = AvatarDirectory(api);
        ref.onDispose(directory.dispose);
        return directory;
      }),
    ]);
    expect(find.text('id null nome null'), findsOneWidget);
    final calls = api.calls.length;
    session.profileImageResult =
        const JellyfinUser(id: 'u1', name: 'Mario', primaryImageTag: 't9');

    await chooseGalleryAvatar(tester);
    await tester.pumpAndSettle();

    // Si rileggono dalla cache, senza chiedere al plugin.
    expect(find.text('id t9 nome t9'), findsOneWidget);
    expect(api.calls, hasLength(calls));
  });
}
