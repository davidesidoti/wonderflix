import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/image_urls.dart';
import 'package:wonderflix/ui/wf_image.dart';

const _hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';

void main() {
  testWidgets('segnaposto: grigio del tema mentre decodifica, mai azzurro',
      (tester) async {
    await tester.pumpWidget(const ImagePlaceholder(blurHash: _hash));
    expect(tester.widget<BlurHash>(find.byType(BlurHash)).color,
        WfColors.surfaceHigh);
  });

  testWidgets('dentro TransparentPlaceholders il segnaposto è trasparente',
      (tester) async {
    await tester.pumpWidget(const TransparentPlaceholders(
      child: Column(children: [
        Expanded(child: ImagePlaceholder(blurHash: _hash)),
        Expanded(child: ImagePlaceholder(icon: Icons.movie)),
      ]),
    ));
    expect(find.byType(BlurHash), findsNothing);
    expect(find.byType(ColoredBox), findsNothing);
    expect(find.byType(Icon), findsNothing);
  });

  // Nei test l'HttpClient risponde 400 a ogni richiesta.
  Widget web() => const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 40,
          height: 60,
          child: _Web(),
        ),
      );

  testWidgets('web: prima del caricamento si vede il blurhash', (tester) async {
    await tester.pumpWidget(web());
    expect(find.byType(BlurHash), findsOneWidget);
  });

  testWidgets('web: se il caricamento fallisce si vede l\'icona di errore',
      (tester) async {
    await tester.pumpWidget(web());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(LucideIcons.imageOff), findsOneWidget);
  });

  testWidgets('web: a immagine caricata non resta nessun segnaposto',
      (tester) async {
    debugNetworkImageHttpClientProvider = () => _PngClient();
    await tester.pumpWidget(web());
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(BlurHash), findsNothing);
    expect(find.byType(ImagePlaceholder), findsNothing);
    // Le invarianti del binding girano prima dei tearDown.
    debugNetworkImageHttpClientProvider = null;
  });
}

// PNG 1x1 trasparente.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

class _PngClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _PngRequest();
}

class _PngRequest extends Fake implements HttpClientRequest {
  @override
  final headers = _Headers();

  @override
  Future<HttpClientResponse> close() async => _PngResponse();
}

class _Headers extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _PngResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => _png.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream.value(_png).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
}

class _Web extends StatelessWidget {
  const _Web();

  @override
  Widget build(BuildContext context) => webNetworkImage(
      const ImageRef('http://localhost/x.jpg', _hash), BoxFit.cover, 80);
}
