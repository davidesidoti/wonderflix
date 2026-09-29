import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../app/providers.dart';
import 'github_releases_api.dart';
import 'release_info.dart';

final _log = Logger('update');

/// Stato dell'aggiornamento.
class UpdateState {
  const UpdateState({
    this.release,
    this.mandatory = false,
    this.progress,
    this.installer,
    this.failed = false,
  });

  /// Versione più nuova trovata; `null` = nessun aggiornamento.
  final ReleaseInfo? release;

  /// La versione installata è sotto `min-version`: l'app va bloccata.
  final bool mandatory;

  /// Download in corso, da 0 a 1.
  final double? progress;

  /// Installer scaricato e verificato.
  final File? installer;

  /// Download non riuscito (lo si mostra solo se obbligatorio).
  final bool failed;

  bool get ready => installer != null;
}

final githubReleasesApiProvider = Provider<GitHubReleasesApi>((ref) {
  final api = GitHubReleasesApi(
      userAgent: 'WonderFlix/${ref.watch(clientInfoProvider).version}');
  ref.onDispose(api.close);
  return api;
});

/// Solo nelle build release: in sviluppo l'app proporrebbe di installare
/// sopra se stessa. Per provarlo: `--dart-define=wfForceUpdateCheck=true`.
final updateChecksEnabledProvider = Provider<bool>((ref) =>
    kReleaseMode || const bool.fromEnvironment('wfForceUpdateCheck'));

/// `%TEMP%\WonderFlix`
final updateDownloadDirectoryProvider = Provider<Directory>((ref) => Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}WonderFlix'));

/// Avvia l'installer in silenzio e chiude l'app. L'installer aspetta che
/// l'app sia chiusa (mutex) e la riapre al termine.
final installUpdateProvider =
    Provider<Future<void> Function(File installer)>((ref) => (installer) async {
          _log.info('avvio dell\'installer e chiusura dell\'app');
          await Process.start(installer.path,
              const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
              mode: ProcessStartMode.detached);
          exit(0);
        });

final _repoPattern = RegExp(r'^[\w.-]+/[\w.-]+$');

/// Controlla gli aggiornamenti all'avvio e ogni [checkInterval]; scarica e
/// verifica l'installer in background. Gli errori finiscono solo nel log e
/// si riprova al controllo successivo.
class UpdateController extends Notifier<UpdateState> {
  static const checkInterval = Duration(hours: 6);

  bool _checking = false;

  @override
  UpdateState build() {
    if (!ref.watch(updateChecksEnabledProvider)) return const UpdateState();
    final timer = Timer.periodic(checkInterval, (_) => unawaited(check()));
    ref.onDispose(timer.cancel);
    scheduleMicrotask(() => unawaited(check()));
    return const UpdateState();
  }

  void _set(UpdateState next) {
    if (ref.mounted) state = next;
  }

  Future<void> check() async {
    if (_checking || !ref.mounted) return;
    _checking = true;
    var mandatory = false;
    try {
      final repo = ref.read(appConfigProvider).githubRepo;
      if (!_repoPattern.hasMatch(repo)) return;
      final api = ref.read(githubReleasesApiProvider);
      final json = await api.latestRelease(repo);
      final release = json == null ? null : parseRelease(json);
      // Nessun aggiornamento: si azzera lo stato (anche quello di "Riprova").
      if (release == null) {
        _set(const UpdateState());
        return;
      }
      final current = Version.parse(ref.read(clientInfoProvider).version);
      if (release.version <= current) {
        _set(const UpdateState());
        return;
      }
      final minVersion = release.minVersion;
      mandatory = minVersion != null && current < minVersion;
      // Installer di questa versione già pronto e ancora su disco: aggiorna
      // solo `mandatory` (può cambiare) senza riscaricare.
      final ready = state.installer;
      if (ready != null &&
          state.release?.version == release.version &&
          await ready.exists()) {
        _set(UpdateState(
            release: release, mandatory: mandatory, installer: ready));
        return;
      }
      _set(UpdateState(release: release, mandatory: mandatory, progress: 0));
      final installer = await _download(api, release, mandatory);
      _set(UpdateState(
          release: release, mandatory: mandatory, installer: installer));
      _log.info('aggiornamento ${release.version} pronto'
          '${mandatory ? ' (obbligatorio)' : ''}');
    } on Object catch (error) {
      _log.warning('aggiornamento non riuscito: $error');
      // Errore prima di un nuovo download: l'installer pronto resta valido.
      if (state.ready) return;
      // Un errore temporaneo non sblocca un aggiornamento già obbligatorio.
      final release = state.release;
      final keep = (mandatory || state.mandatory) && release != null;
      _set(keep
          ? UpdateState(release: release, mandatory: true, failed: true)
          : const UpdateState());
    } finally {
      _checking = false;
    }
  }

  /// Nuovo tentativo dopo un download fallito (schermata bloccante).
  void retry() {
    final release = state.release;
    if (release == null) return;
    _set(UpdateState(release: release, mandatory: state.mandatory, progress: 0));
    unawaited(check());
  }

  Future<void> install() async {
    final installer = state.installer;
    if (installer == null) return;
    try {
      if (await installer.exists()) {
        await ref.read(installUpdateProvider)(installer);
        return;
      }
      _log.warning('installer non più presente: si riscarica');
    } on Object catch (error) {
      // Niente `$error`: conterrebbe il percorso (con il nome utente).
      _log.warning('avvio dell\'installer non riuscito (${error.runtimeType})');
    }
    // Si torna allo stato del download e si riparte dal controllo.
    final release = state.release;
    _set(state.mandatory && release != null
        ? UpdateState(release: release, mandatory: true, failed: true)
        : const UpdateState());
    unawaited(check());
  }

  Future<File> _download(
      GitHubReleasesApi api, ReleaseInfo release, bool mandatory) async {
    final expected = parseSha256File(await api.downloadText(release.checksumUrl));
    if (expected == null) throw const FormatException('file .sha256 non valido');
    final directory = ref.read(updateDownloadDirectoryProvider);
    await directory.create(recursive: true);
    final target = File(
        '${directory.path}${Platform.pathSeparator}${release.installerName}');
    await _deleteOtherInstallers(directory, target);
    if (await target.exists() && await sha256OfFile(target) == expected) {
      return target;
    }
    final partial = File('${target.path}.part');
    await api.downloadFile(release.installerUrl, partial,
        onProgress: (progress) => _set(UpdateState(
            release: release, mandatory: mandatory, progress: progress)));
    if (await sha256OfFile(partial) != expected) {
      await partial.delete();
      throw StateError('SHA-256 dell\'installer ${release.version} non valido');
    }
    if (await target.exists()) await target.delete();
    return partial.rename(target.path);
  }

  /// Installer di versioni precedenti rimasti in `%TEMP%\WonderFlix`.
  Future<void> _deleteOtherInstallers(Directory directory, File keep) async {
    await for (final entity in directory.list()) {
      final name = entity.uri.pathSegments.last;
      if (entity is File &&
          name.startsWith('WonderFlix-Setup-') &&
          entity.path != keep.path) {
        try {
          await entity.delete();
        } on FileSystemException {
          // In uso o già eliminato: non importa.
        }
      }
    }
  }
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
