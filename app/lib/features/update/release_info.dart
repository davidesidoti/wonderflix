import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pub_semver/pub_semver.dart';

/// Una release di WonderFlix pubblicata su GitHub, con l'installer.
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.notes,
    required this.minVersion,
    required this.installerName,
    required this.installerUrl,
    required this.checksumUrl,
  });

  final Version version;

  /// Note di rilascio in markdown, senza il marcatore `min-version`.
  final String notes;

  /// Versione minima ancora accettata; sotto, l'aggiornamento è obbligatorio.
  final Version? minVersion;

  /// `WonderFlix-Setup-X.Y.Z.exe`
  final String installerName;
  final Uri installerUrl;

  /// File `.sha256` dell'installer.
  final Uri checksumUrl;
}

/// Legge la risposta di `releases/latest`. `null` se non è una release
/// utilizzabile: bozza, pre-release, tag non semver o file mancanti.
ReleaseInfo? parseRelease(Map<String, dynamic> json) {
  if (json['draft'] == true || json['prerelease'] == true) return null;
  final tag = json['tag_name'];
  if (tag is! String) return null;
  final Version version;
  try {
    version = Version.parse(tag.startsWith('v') ? tag.substring(1) : tag);
  } on FormatException {
    return null;
  }
  if (version.isPreRelease) return null;

  final installerName = 'WonderFlix-Setup-$version.exe';
  Uri? installerUrl;
  Uri? checksumUrl;
  final assets = json['assets'];
  if (assets is List) {
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is! String || url is! String) continue;
      if (name == installerName) installerUrl = Uri.tryParse(url);
      if (name == '$installerName.sha256') checksumUrl = Uri.tryParse(url);
    }
  }
  if (installerUrl == null || checksumUrl == null) return null;

  final body = json['body'];
  final notes = body is String ? body : '';
  return ReleaseInfo(
    version: version,
    notes: releaseNotesForDisplay(notes),
    minVersion: minVersionFrom(notes),
    installerName: installerName,
    installerUrl: installerUrl,
    checksumUrl: checksumUrl,
  );
}

final _minVersionMarker =
    RegExp(r'<!--\s*wonderflix:min-version=([^\s>]+)\s*-->');

/// Versione del marcatore `<!-- wonderflix:min-version=X.Y.Z -->`.
Version? minVersionFrom(String notes) {
  final match = _minVersionMarker.firstMatch(notes);
  if (match == null) return null;
  try {
    return Version.parse(match[1]!);
  } on FormatException {
    return null;
  }
}

/// Le note da mostrare: senza il marcatore.
String releaseNotesForDisplay(String notes) =>
    notes.replaceAll(_minVersionMarker, '').trim();

final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

/// L'hash di un file `.sha256` (`<hash>  <nome file>`), in minuscolo.
String? parseSha256File(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final hash = trimmed.split(RegExp(r'\s+')).first.toLowerCase();
  return _sha256Hex.hasMatch(hash) ? hash : null;
}

/// SHA-256 esadecimale minuscolo del contenuto di [file].
Future<String> sha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
