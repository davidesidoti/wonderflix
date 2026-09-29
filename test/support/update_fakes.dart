import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:wonderflix/features/update/github_releases_api.dart';
import 'package:wonderflix/features/update/release_info.dart';
import 'package:wonderflix/features/update/update_controller.dart';

/// Una release di prova.
ReleaseInfo testRelease({
  String version = '0.2.0',
  String notes = '## Novità\n- Più veloce',
  String? minVersion,
}) =>
    ReleaseInfo(
      version: Version.parse(version),
      notes: notes,
      minVersion: minVersion == null ? null : Version.parse(minVersion),
      installerName: 'WonderFlix-Setup-$version.exe',
      installerUrl: Uri.parse('https://x/WonderFlix-Setup-$version.exe'),
      checksumUrl: Uri.parse('https://x/WonderFlix-Setup-$version.exe.sha256'),
    );

/// Il JSON di `releases/latest` per [version].
Map<String, dynamic> latestJson(String version, {String body = 'Note'}) => {
      'tag_name': 'v$version',
      'body': body,
      'draft': false,
      'prerelease': false,
      'assets': [
        {
          'name': 'WonderFlix-Setup-$version.exe',
          'browser_download_url': 'https://x/WonderFlix-Setup-$version.exe',
        },
        {
          'name': 'WonderFlix-Setup-$version.exe.sha256',
          'browser_download_url':
              'https://x/WonderFlix-Setup-$version.exe.sha256',
        },
      ],
    };

/// SHA-256 di `[1, 2, 3]`, i byte dell'installer finto.
const fakeInstallerSha256 =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';

/// GitHub in memoria.
class FakeGitHubReleasesApi implements GitHubReleasesApi {
  Map<String, dynamic>? latest;
  String checksum = '$fakeInstallerSha256  WonderFlix-Setup.exe';
  List<int> installerBytes = const [1, 2, 3];

  /// Se valorizzato, [latestRelease] lancia questo errore.
  Object? latestError;

  /// Se valorizzato, [downloadFile] lancia questo errore.
  Object? downloadError;
  int latestCalls = 0;
  int downloads = 0;

  @override
  Future<Map<String, dynamic>?> latestRelease(String repo) async {
    latestCalls++;
    final error = latestError;
    if (error != null) throw error;
    return latest;
  }

  @override
  Future<String> downloadText(Uri url) async => checksum;

  @override
  Future<void> downloadFile(Uri url, File target,
      {void Function(double progress)? onProgress}) async {
    downloads++;
    final error = downloadError;
    if (error != null) throw error;
    onProgress?.call(0.5);
    await target.writeAsBytes(installerBytes);
    onProgress?.call(1.0);
  }

  @override
  void close() {}
}

/// Controller con uno stato fisso: registra installazioni e nuovi tentativi.
class FakeUpdateController extends UpdateController {
  FakeUpdateController(this.initial);

  final UpdateState initial;
  int installs = 0;
  int retries = 0;

  @override
  UpdateState build() => initial;

  void emit(UpdateState next) => state = next;

  @override
  Future<void> install() async => installs++;

  @override
  void retry() => retries++;
}
