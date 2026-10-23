/// Aggiunge il token come `ApiKey` alla query di [url] (nel browser le
/// richieste dei media non possono portare l'header `Authorization`).
/// Se c'è già un `ApiKey` (anche con altre maiuscole) l'URL resta uguale;
/// `api_key` è un altro parametro e Jellyfin 10.11 lo ignora.
String withApiKey(String url, String token) {
  final uri = Uri.parse(url);
  if (uri.queryParameters.keys.any((k) => k.toLowerCase() == 'apikey')) {
    return url;
  }
  return uri
      .replace(queryParameters: {...uri.queryParameters, 'ApiKey': token})
      .toString();
}
