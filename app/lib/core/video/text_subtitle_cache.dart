import 'package:dio/dio.dart';

import 'vtt.dart';

/// I cue dei sottotitoli di testo (VTT/SRT), scaricati una volta per URL.
///
/// Alla prima richiesta di un sottotitolo interno Jellyfin estrae dal file
/// tutti quelli di testo: con un file grande la risposta tarda anche minuti
/// (4 per un MKV da 1080p con 6 SRT). Una richiesta in corso si condivide;
/// una fallita si dimentica, così la scelta dopo riprova.
class TextSubtitleCache {
  TextSubtitleCache({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  final _cues = <String, Future<List<VttCue>>>{};

  Future<List<VttCue>> load(String url, Map<String, String> headers) {
    final known = _cues[url];
    if (known != null) return known;
    final cues = _download(url, headers);
    _cues[url] = cues;
    cues.then((_) {}, onError: (Object _) {
      if (identical(_cues[url], cues)) _cues.remove(url);
    });
    return cues;
  }

  Future<List<VttCue>> _download(
      String url, Map<String, String> headers) async {
    final response = await _dio.get<String>(
      url,
      options: Options(headers: headers, responseType: ResponseType.plain),
    );
    return parseVtt(response.data ?? '');
  }

  void clear() => _cues.clear();
}
