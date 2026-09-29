import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'client_info.dart';

/// Accesso HTTP a Jellyfin: aggiunge l'header di autenticazione, converte gli
/// errori in [ApiException] e segnala i 401 di una sessione attiva.
class JellyfinHttp {
  JellyfinHttp({
    required Uri baseUrl,
    required ClientInfo clientInfo,
    HttpClientAdapter? adapter,
  })  : _clientInfo = clientInfo,
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
  final ClientInfo _clientInfo;

  /// Token della sessione corrente, `null` se non autenticati.
  String? token;

  /// Chiamato quando una richiesta fatta con un token riceve 401.
  void Function()? onUnauthorized;

  String get authorizationHeader =>
      buildAuthorizationHeader(_clientInfo, token: token);

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _send(() => dio.get<dynamic>(path,
          queryParameters: query, cancelToken: cancelToken));

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      _send(() => dio.post<dynamic>(path, data: body, queryParameters: query));

  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) =>
      _send(() => dio.delete<dynamic>(path, queryParameters: query));

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    final sentToken = token;
    try {
      final response = await request();
      return response.data;
    } on DioException catch (e) {
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
