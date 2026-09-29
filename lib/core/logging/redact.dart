/// Toglie da un testo di log token, password e header di autenticazione.
/// Meglio togliere troppo che troppo poco: il log si allega alle richieste
/// di aiuto.
String redactSecrets(String text) {
  var result = text;
  for (final (pattern, replace) in _rules) {
    result = result.replaceAllMapped(pattern, replace);
  }
  return result;
}

final _rules = <(RegExp, String Function(Match))>[
  // Header MediaBrowser: Token="…"
  (RegExp(r'Token="[^"]*"'), (_) => 'Token="***"'),
  // Parametri dell'indirizzo: api_key=…, ApiKey=…, access_token=…
  (
    RegExp(r'\b(api_key|ApiKey|access_token|X-Emby-Token|X-MediaBrowser-Token)=[^&\s"]+',
        caseSensitive: false),
    (m) => '${m[1]}=***',
  ),
  // JSON: "AccessToken": "…", "Pw": "…", "Password": "…", "Token": "…"
  (
    RegExp(r'"(AccessToken|Pw|Password|Token)"\s*:\s*"[^"]*"',
        caseSensitive: false),
    (m) => '"${m[1]}":"***"',
  ),
  // Header scritto per intero: tutto fino a fine riga.
  (
    RegExp(r'(Authorization["\x27]?\s*[:=]\s*)[^\n]*', caseSensitive: false),
    (m) => '${m[1]}***',
  ),
];
