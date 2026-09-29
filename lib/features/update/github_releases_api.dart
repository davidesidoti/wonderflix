import 'dart:io';

import 'package:dio/dio.dart';

/// Release pubbliche su GitHub, senza token. Un `Dio` separato da quello di
/// Jellyfin: niente header di autenticazione verso GitHub.
class GitHubReleasesApi {
  GitHubReleasesApi({required String userAgent, HttpClientAdapter? adapter})
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
          headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': userAgent,
          },
        )) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  final Dio _dio;

  /// Ultima release pubblicata (esclude bozze e pre-release); `null` se il
  /// repository non ne ha ancora (404).
  Future<Map<String, dynamic>?> latestRelease(String repo) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
          'https://api.github.com/repos/$repo/releases/latest');
      return response.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<String> downloadText(Uri url) async {
    final response = await _dio.getUri<String>(url,
        options: Options(responseType: ResponseType.plain));
    return response.data ?? '';
  }

  /// Scarica [url] in [target]; [onProgress] riceve valori da 0 a 1.
  Future<void> downloadFile(Uri url, File target,
      {void Function(double progress)? onProgress}) async {
    await _dio.downloadUri(url, target.path,
        onReceiveProgress: (received, total) {
      if (total > 0) onProgress?.call(received / total);
    });
  }

  void close() => _dio.close();
}
