import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import 'api_exception.dart';
import 'client_info.dart';

final _log = Logger('http');

/// Le risposte di nginx mentre Jellyfin si riavvia (502, 503, 504): sono
/// esiti attesi, quindi chi li aspetta li passa come `quietStatuses` (nel log
/// come info) e li legge come "Jellyfin non c'è ancora".
const restartGatewayStatuses = {502, 503, 504};

/// Accesso HTTP a Jellyfin: aggiunge l'header di autenticazione, converte gli
/// errori in [ApiException] e segnala i 401 di una sessione attiva.
class JellyfinHttp {
  JellyfinHttp({
    required Uri baseUrl,
    required ClientInfo clientInfo,
    HttpClientAdapter? adapter,
  })  : _baseUrl = baseUrl,
        _clientInfo = clientInfo,
        dio = Dio(BaseOptions(
          baseUrl: baseUrl.toString(),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          responseType: ResponseType.json,
        )) {
    if (adapter != null) dio.httpClientAdapter = adapter;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      options.headers['Authorization'] = authorizationHeader;
      handler.next(options);
    }));
  }

  final Dio dio;
  final Uri _baseUrl;
  final ClientInfo _clientInfo;

  String? _token;

  /// Token della sessione corrente, `null` se non autenticati. Cambia solo
  /// con [setCredentials].
  String? get token => _token;

  /// DeviceId del profilo attivo (spec K §9.2); `null`: quello
  /// dell'installazione (`ClientInfo.deviceId`).
  String? _deviceId;

  /// Il DeviceId che va nelle richieste.
  String get deviceId => _deviceId ?? _clientInfo.deviceId;

  /// Token e DeviceId del profilo attivo cambiano insieme (spec K §9.2). Con
  /// `null` si torna a nessun token e al DeviceId dell'installazione.
  void setCredentials({required String? token, required String? deviceId}) {
    _token = token;
    _deviceId = deviceId;
  }

  /// Un client per le chiamate di un profilo non attivo (spec K §9.2): stesso
  /// server e stesso adattatore, le credenziali di quel profilo. Non tocca
  /// quelle di questo client e non segnala i 401 (nessun `onUnauthorized`).
  JellyfinHttp withCredentials(
          {required String token, required String deviceId}) =>
      JellyfinHttp(
        baseUrl: _baseUrl,
        clientInfo: _clientInfo,
        adapter: _BorrowedAdapter(dio.httpClientAdapter),
      )..setCredentials(token: token, deviceId: deviceId);

  /// Chiamato quando una richiesta fatta con un token riceve 401.
  void Function()? onUnauthorized;

  String get authorizationHeader => buildAuthorizationHeader(
      _clientInfo.copyWith(deviceId: deviceId),
      token: token);

  /// Con [quietStatuses] le risposte con quei codici, attese da chi chiama,
  /// vanno nel log come info e non tra gli errori.
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    Set<int> quietStatuses = const {},
  }) =>
      _send(
          () => dio.get<dynamic>(path,
              queryParameters: query, cancelToken: cancelToken),
          quietStatuses: quietStatuses);

  /// [quietStatuses] come in [get]. [contentType] per un corpo che non è
  /// JSON (l'immagine di un utente, spec K §10.4): senza, dio manda
  /// `application/json`.
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    String? contentType,
    Set<int> quietStatuses = const {},
  }) =>
      _send(
          () => dio.post<dynamic>(path,
              data: body,
              queryParameters: query,
              options:
                  contentType == null ? null : Options(contentType: contentType)),
          quietStatuses: quietStatuses);

  Future<dynamic> delete(String path,
          {Map<String, dynamic>? query, Set<int> quietStatuses = const {}}) =>
      _send(() => dio.delete<dynamic>(path, queryParameters: query),
          quietStatuses: quietStatuses);

  Future<dynamic> _send(Future<Response<dynamic>> Function() request,
      {Set<int> quietStatuses = const {}}) async {
    final sentToken = token;
    try {
      final response = await request();
      return response.data;
    } on DioException catch (e) {
      // Solo metodo, percorso ed esito: query e header possono contenere
      // token. Le richieste annullate non sono errori.
      if (e.type != DioExceptionType.cancel) {
        final status = e.response?.statusCode;
        _log.log(
            quietStatuses.contains(status) ? Level.INFO : Level.WARNING,
            '${e.requestOptions.method} ${e.requestOptions.path}: '
            '${status ?? e.type.name}');
      }
      final mapped = mapDioException(e);
      if (mapped is UnauthorizedException &&
          sentToken != null &&
          sentToken == token) {
        onUnauthorized?.call();
      }
      throw mapped;
    }
  }
}

/// L'adattatore di un altro client, in prestito: le richieste passano da lì,
/// ma `close` non fa niente. L'adattatore è del client principale: chiuderlo
/// qui fermerebbe anche lui.
class _BorrowedAdapter implements HttpClientAdapter {
  _BorrowedAdapter(this._inner);

  final HttpClientAdapter _inner;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      _inner.fetch(options, requestStream, cancelFuture);

  @override
  void close({bool force = false}) {}
}

/// Converte il corpo di una risposta in oggetto JSON, o lancia
/// [ServerErrorException] se la forma non è quella attesa.
Map<String, dynamic> asJsonMap(Object? data) {
  if (data is Map<String, dynamic>) return data;
  throw const ServerErrorException(null);
}

/// Converte il corpo in un modello; forme inattese diventano [ServerErrorException].
T parseJson<T>(Object? data, T Function(Map<String, dynamic> json) fromJson) {
  try {
    return fromJson(asJsonMap(data));
  } on ApiException {
    rethrow;
  } on Object {
    throw const ServerErrorException(null);
  }
}
