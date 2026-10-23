import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:web/web.dart' as web;

import 'subtitle_kind.dart';
import 'vtt.dart';

final _log = Logger('player');

const _octopusDir = 'vendor/libass-wasm-4.2.4';
const _bitsubModule = 'vendor/libbitsub-1.11.0/dist/index.js';

/// SubtitlesOctopus di libass-wasm, caricato da `web/index.html`.
@JS('SubtitlesOctopus')
extension type _Octopus._(JSObject _) implements _Graphic {
  external _Octopus(_OctopusOptions options);
}

extension type _OctopusOptions._(JSObject _) implements JSObject {
  external factory _OctopusOptions({
    web.HTMLVideoElement video,
    String subUrl,
    String workerUrl,
    JSArray<JSString> fonts,
    String fallbackFont,
    String renderMode,
    int libassMemoryLimit,
    double prescaleFactor,
    int maxRenderHeight,
    int renderAhead,
    double timeOffset,
    JSFunction onError,
  });
}

/// `PgsRenderer` e `VobSubRenderer` di libbitsub.
extension type _BitsubOptions._(JSObject _) implements JSObject {
  external factory _BitsubOptions({
    web.HTMLVideoElement video,
    String subUrl,
    String fileName,
    bool streamingLoad,
    bool rangeRequests,
    double timeOffset,
    JSFunction onError,
  });
}

/// Ciò che Octopus e libbitsub hanno in comune: il tempo del sottotitolo è
/// `currentTime + timeOffset` (secondi).
extension type _Graphic._(JSObject _) implements JSObject {
  external set timeOffset(double value);

  external void dispose();
}

/// Sottotitoli esterni del player web: il testo (VTT/SRT) lo disegna Flutter
/// sopra il video ([view]), ASS e PGS/VobSub dei canvas accanto al
/// `<video>`, dentro il suo contenitore.
class WebSubtitles {
  WebSubtitles(this._video);

  final web.HTMLVideoElement _video;

  /// Header della sorgente aperta (`Authorization`), per scaricare il testo.
  Map<String, String> headers = const {};

  /// L'id è la posizione nella lista: stabile finché il video resta aperto.
  final _urls = <String>[];
  final _cues = <String, List<VttCue>>{};
  int _selection = 0;
  Duration _delay = Duration.zero;
  _Graphic? _graphic;
  List<VttCue>? _text;
  Timer? _ticker;
  final _line = ValueNotifier<String>('');
  final _scale = ValueNotifier<double>(1);
  static Future<JSObject>? _bitsub;

  /// Carica e mostra [url]; `null` se il browser non sa disegnarlo o non si è
  /// caricato (resta quello di prima).
  Future<String?> add(String url) async {
    if (subtitleKindForUrl(url) == null) return null;
    var index = _urls.indexOf(url);
    if (index < 0) {
      index = _urls.length;
      _urls.add(url);
    }
    final id = '$index';
    return await select(id) ? id : null;
  }

  /// Mostra [id] e nasconde gli altri; `null` li nasconde tutti.
  Future<bool> select(String? id) async {
    final selection = ++_selection;
    final url = id == null ? null : _urls.elementAtOrNull(int.parse(id));
    if (url == null) {
      _show();
      return id == null;
    }
    try {
      switch (subtitleKindForUrl(url)!) {
        case SubtitleKind.text:
          final cues = _cues[id!] ??= parseVtt(
            (await Dio().get<String>(
              url,
              options: Options(
                headers: headers,
                responseType: ResponseType.plain,
              ),
            )).data!,
          );
          if (selection == _selection) _show(text: cues);
        case SubtitleKind.ass:
          final fonts = await _fallbackFonts(url);
          if (selection == _selection) _show(graphic: _octopus(url, fonts));
        case final kind:
          final JSObject module;
          try {
            module = await (_bitsub ??= importModule(
              _resolve(_bitsubModule).toJS,
            ).toDart);
          } on Object {
            _bitsub = null; // Un import fallito si riprova alla scelta dopo.
            rethrow;
          }
          final name = kind == SubtitleKind.pgs
              ? 'PgsRenderer'
              : 'VobSubRenderer';
          if (selection == _selection) {
            _show(graphic: _bitsubRenderer(module, name, url));
          }
      }
      return true;
    } on Object catch (error) {
      _log.warning('sottotitolo non caricato ($url): $error');
      return false;
    }
  }

  /// Tiene al più un sottotitolo attivo: gli altri si ricreano alla scelta.
  void _show({List<VttCue>? text, _Graphic? graphic}) {
    _graphic?.dispose();
    _graphic = graphic;
    _text = text;
    _ticker?.cancel();
    _ticker = text == null
        ? null
        : Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    _tick();
  }

  void _tick() {
    final text = _text;
    if (text == null) {
      _line.value = '';
      return;
    }
    final time =
        Duration(microseconds: (_video.currentTime * 1e6).round()) - _delay;
    _line.value = [
      for (final cue in text)
        if (cue.start <= time && time < cue.end) cue.text,
    ].join('\n');
  }

  _Graphic _octopus(String url, List<String> fonts) => _Octopus(
    _OctopusOptions(
      video: _video,
      subUrl: url,
      workerUrl: _resolve('$_octopusDir/subtitles-octopus-worker.js'),
      fonts: [for (final font in fonts) font.toJS].toJS,
      fallbackFont: _resolve('$_octopusDir/default.woff2'),
      // Come jellyfin-web.
      renderMode: 'wasm-blend',
      libassMemoryLimit: 40,
      prescaleFactor: 0.8,
      maxRenderHeight: 2160,
      renderAhead: 90,
      timeOffset: _offset,
      onError: (() => _log.warning('libass: errore con $url')).toJS,
    ),
  );

  _Graphic _bitsubRenderer(JSObject module, String name, String url) =>
      (module[name]! as JSFunction).callAsConstructor<_Graphic>(
        _BitsubOptions(
          video: _video,
          subUrl: url,
          // Senza query: libbitsub riconosce un `.mks` dal nome.
          fileName: Uri.parse(url).pathSegments.last,
          streamingLoad: true,
          rangeRequests: true,
          timeOffset: _offset,
          onError: ((JSAny? error) => _log.warning(
            'libbitsub: $error con $url',
          )).toJS,
        ),
      );

  /// I font del server (`/FallbackFont/Fonts`), come jellyfin-web. Il modello
  /// non espone gli allegati del file, quindi non ci sono i font propri.
  Future<List<String>> _fallbackFonts(String subtitleUrl) async {
    final uri = Uri.parse(subtitleUrl);
    try {
      // shortcut: la radice del server si ricava dall'URL del sottotitolo
      // (`…/Videos/…`), finché il motore non riceve l'URL del server.
      final root = subtitleUrl.substring(0, subtitleUrl.indexOf('/Videos/'));
      final response = await Dio().get<List<dynamic>>(
        '$root/FallbackFont/Fonts',
        options: Options(headers: headers),
      );
      return [
        for (final font in response.data ?? const [])
          if (font is Map && font['Name'] is String)
            Uri.parse(
              '$root/FallbackFont/Fonts/${Uri.encodeComponent(font['Name'] as String)}',
            ).replace(queryParameters: uri.queryParameters).toString(),
      ];
    } on Object catch (error) {
      _log.info('font di riserva non disponibili: $error');
      return const [];
    }
  }

  double get _offset => -_delay.inMicroseconds / 1e6;

  /// Positivo = sottotitoli più tardi.
  void setDelay(Duration delay) {
    _delay = delay;
    _graphic?.timeOffset = _offset;
    _tick();
  }

  void setScale(double scale) => _scale.value = scale;

  /// Dimentica i sottotitoli del video chiuso.
  void clear() {
    ++_selection;
    _show();
    _urls.clear();
    _cues.clear();
  }

  /// Il testo sopra il video: bianco con contorno, in basso al centro.
  Widget view() => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, constraints) => ListenableBuilder(
        listenable: Listenable.merge([_line, _scale]),
        builder: (context, _) {
          if (_line.value.isEmpty) return const SizedBox.expand();
          final size = constraints.maxHeight * 0.055 * _scale.value;
          final style = TextStyle(
            fontSize: size,
            height: 1.2,
            fontWeight: FontWeight.w600,
          );
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                0,
                24,
                constraints.maxHeight * 0.06,
              ),
              child: Stack(
                children: [
                  Text(
                    _line.value,
                    textAlign: TextAlign.center,
                    style: style.copyWith(
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = size / 8
                        ..strokeJoin = StrokeJoin.round
                        ..color = const Color(0xFF000000),
                    ),
                  ),
                  Text(
                    _line.value,
                    textAlign: TextAlign.center,
                    style: style.copyWith(color: const Color(0xFFFFFFFF)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// URL di un file di `web/` (rispetta il `<base href>`).
String _resolve(String path) =>
    Uri.parse(web.document.baseURI).resolve(path).toString();
