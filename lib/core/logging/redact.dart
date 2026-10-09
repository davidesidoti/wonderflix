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
  (
    RegExp(r'(Token)="[^"]*"', caseSensitive: false),
    (m) => '${m[1]}="***"',
  ),
  // Parametri dell'indirizzo: api_key=…, ApiKey=…, access_token=…
  (
    RegExp(r'\b(api_key|ApiKey|access_token|X-Emby-Token|X-MediaBrowser-Token)=[^&\s"]+',
        caseSensitive: false),
    (m) => '${m[1]}=***',
  ),
  // Gli stessi nomi in una mappa o in JSON: {X-Emby-Token: …}, "api_key":"…"
  (
    RegExp(
        r'''(["']?)\b(api_key|ApiKey|access_token|X-Emby-Token|X-MediaBrowser-Token)\1(\s*:\s*)("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[^,}\]\s&"']+)''',
        caseSensitive: false),
    (m) {
      final quote = m[4]!.startsWith('"') || m[4]!.startsWith("'")
          ? m[4]![0]
          : '';
      return '${m[1]}${m[2]}${m[1]}${m[3]}$quote***$quote';
    },
  ),
  // JSON: "AccessToken": "…", "Pw": "…", "Password": "…", "Token": "…", e
  // i corpi del recupero e dei contatti (spec L §8): il codice, le
  // password, il contatto (un nome Discord o un'email).
  (
    RegExp(
        r'"(AccessToken|Pw|Password|Token|CurrentPw|NewPw|NewPassword|Code|Target)"\s*:\s*"(?:[^"\\]|\\.)*"',
        caseSensitive: false),
    (m) => '"${m[1]}":"***"',
  ),
  // Header scritto per intero: tutto fino a fine riga.
  (
    RegExp(r'(Authorization["\x27]?\s*[:=]\s*)[^\n]*', caseSensitive: false),
    (m) => '${m[1]}***',
  ),
];
