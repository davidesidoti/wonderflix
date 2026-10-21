import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/media_info_models.dart';
import '../../core/jellyfin/user_config_api.dart';
import '../../core/subtitles/subtitle_models.dart';
import '../../core/subtitles/subtitles_api.dart';
import '../admin/admin_providers.dart';
import '../auth/session_controller.dart';
import '../library/library_providers.dart';
import '../reports/reports_providers.dart';
import '../settings/language_preferences.dart';
import 'subtitle_file_picker.dart';

final _log = Logger('subtitles');

/// Ogni quanto si rilegge l'elenco delle tracce dopo uno scarico o un
/// caricamento: il plugin mette in coda il refresh di Jellyfin.
const subtitlePollInterval = Duration(seconds: 2);

/// Dopo questo tempo si smette di aspettare la traccia nuova.
const subtitlePollTimeout = Duration(seconds: 20);

/// Lingua della ricerca quando l'utente non ne ha una fra quelle del menu.
const _fallbackLanguage = 'ita';

/// L'avviso della finestra, sopra le tracce.
enum SubtitlesNotice {
  none,
  downloadFailed,
  uploadFailed,
  fileTooLarge,
  noPermission,
  error,
  waiting,
  trackAdded,
  trackSoon,
}

const _keep = Object();

class SubtitlesState {
  const SubtitlesState({
    required this.language,
    this.searching = false,
    this.results,
    this.busyId,
    this.uploading = false,
    this.notice = SubtitlesNotice.none,
    this.error,
  });

  /// Codice a tre lettere, una chiave di `playbackLanguages`.
  final String language;
  final bool searching;

  /// `null` finché non si è cercato.
  final List<RemoteSubtitle>? results;

  /// Il risultato in scarico o in attesa della traccia.
  final String? busyId;
  final bool uploading;
  final SubtitlesNotice notice;

  /// Con [SubtitlesNotice.error], la causa.
  final Object? error;

  /// `results`, `busyId` e `error` si azzerano passando `null`.
  SubtitlesState copyWith({
    String? language,
    bool? searching,
    Object? results = _keep,
    Object? busyId = _keep,
    bool? uploading,
    SubtitlesNotice? notice,
    Object? error = _keep,
  }) => SubtitlesState(
    language: language ?? this.language,
    searching: searching ?? this.searching,
    results: identical(results, _keep)
        ? this.results
        : results as List<RemoteSubtitle>?,
    busyId: identical(busyId, _keep) ? this.busyId : busyId as String?,
    uploading: uploading ?? this.uploading,
    notice: notice ?? this.notice,
    error: identical(error, _keep) ? this.error : error,
  );
}

/// Cerca, scarica, carica ed elimina i sottotitoli di un titolo. Una sola
/// operazione alla volta; le attese si fermano con la finestra.
class SubtitlesController extends Notifier<SubtitlesState> {
  SubtitlesController(this.itemId);

  final String itemId;
  bool _languageChosen = false;
  bool _deleting = false;
  Timer? _timer;
  late SessionController _session;

  @override
  SubtitlesState build() {
    ref.onDispose(() => _timer?.cancel());
    _session = ref.read(sessionControllerProvider.notifier);
    // La preferenza può arrivare dopo l'apertura: vale finché non si sceglie.
    ref.listen(languagePreferencesProvider, (_, next) {
      if (!_languageChosen) {
        state = state.copyWith(language: _initialLanguage(next.value));
      }
    });
    return SubtitlesState(
      language: _initialLanguage(ref.read(languagePreferencesProvider).value),
    );
  }

  static String _initialLanguage(LanguagePreferences? preferences) {
    final preferred = preferences?.subtitleLanguage;
    return preferred != null && playbackLanguages.containsKey(preferred)
        ? preferred
        : _fallbackLanguage;
  }

  bool get _busy =>
      state.searching || state.busyId != null || state.uploading || _deleting;

  void setLanguage(String code) {
    _languageChosen = true;
    // I risultati sono di un'altra lingua.
    state = state.copyWith(language: code, results: null);
  }

  Future<void> search() async {
    if (_busy) return;
    final ref = this.ref;
    state = state.copyWith(
      searching: true,
      notice: SubtitlesNotice.none,
      error: null,
    );
    try {
      final found = await ref
          .read(subtitlesApiProvider)
          .search(itemId, state.language);
      if (!ref.mounted) return;
      state = state.copyWith(
        searching: false,
        results: sortSubtitles(found),
        error: null,
      );
    } on Object catch (error) {
      _fail(ref, error, SubtitlesNotice.error);
    }
  }

  /// Vero quando la traccia nuova è comparsa.
  Future<bool> download(RemoteSubtitle subtitle) => _addTrack(
    busyId: subtitle.id,
    failure: SubtitlesNotice.downloadFailed,
    call: (api) => api.download(itemId, subtitle.id),
  );

  /// Vero quando la traccia nuova è comparsa. Il formato è l'estensione del
  /// nome, la lingua quella del menu.
  Future<bool> upload(
    PickedSubtitleFile file, {
    required bool forced,
    required bool hearingImpaired,
  }) {
    if (_busy) return Future.value(false);
    if (file.length > maxSubtitleFileBytes) {
      state = state.copyWith(notice: SubtitlesNotice.fileTooLarge);
      return Future.value(false);
    }
    final language = state.language;
    final dot = file.name.lastIndexOf('.');
    final format = dot < 0 ? '' : file.name.substring(dot + 1).toLowerCase();
    return _addTrack(
      uploading: true,
      failure: SubtitlesNotice.uploadFailed,
      call: (api) async => api.upload(
        itemId,
        SubtitleUpload(
          language: language,
          format: format,
          isForced: forced,
          isHearingImpaired: hearingImpaired,
          bytes: await file.read(),
        ),
      ),
    );
  }

  /// Solo l'admin e solo le tracce esterne; la conferma la chiede la finestra.
  Future<void> delete(SubtitleTrack track) async {
    final ref = this.ref;
    if (_busy || !track.isExternal || !ref.read(isAdminProvider)) return;
    _deleting = true;
    state = state.copyWith(notice: SubtitlesNotice.none, error: null);
    try {
      await ref.read(subtitlesApiProvider).delete(itemId, track.index);
      if (ref.mounted) ref.invalidate(itemMediaInfoProvider(itemId));
    } on Object catch (error) {
      _fail(ref, error, SubtitlesNotice.error);
    } finally {
      _deleting = false;
    }
  }

  Future<bool> _addTrack({
    String? busyId,
    bool uploading = false,
    required SubtitlesNotice failure,
    required Future<void> Function(SubtitlesApi api) call,
  }) async {
    if (_busy) return false;
    final ref = this.ref;
    state = state.copyWith(
      busyId: busyId,
      uploading: uploading,
      notice: SubtitlesNotice.none,
      error: null,
    );
    try {
      // Prima della chiamata: per riconoscere la traccia nuova.
      final before = await _externalIndexes(ref);
      if (!ref.mounted) return false;
      await call(ref.read(subtitlesApiProvider));
      if (!ref.mounted) return false;
      state = state.copyWith(notice: SubtitlesNotice.waiting);
      final found = await _waitForNewTrack(ref, before);
      if (!ref.mounted) return false;
      state = state.copyWith(
        busyId: null,
        uploading: false,
        notice: found ? SubtitlesNotice.trackAdded : SubtitlesNotice.trackSoon,
      );
      if (found) ref.invalidate(itemMediaInfoProvider(itemId));
      return found;
    } on Object catch (error) {
      _fail(ref, error, failure);
      return false;
    }
  }

  Future<Set<int>> _externalIndexes(Ref ref) async => externalSubtitleIndexes(
    await ref
        .read(libraryApiProvider)
        .mediaInfo(ref.read(currentUserIdProvider), itemId),
  );

  /// Rilegge ogni [subtitlePollInterval], al massimo per
  /// [subtitlePollTimeout]. Se la finestra si chiude il timer si ferma e
  /// l'attesa non finisce: nessuno la sta più aspettando.
  Future<bool> _waitForNewTrack(Ref ref, Set<int> before) async {
    for (
      var waited = Duration.zero;
      waited < subtitlePollTimeout;
      waited += subtitlePollInterval
    ) {
      final tick = Completer<void>();
      _timer = Timer(subtitlePollInterval, tick.complete);
      await tick.future;
      try {
        final now = await _externalIndexes(ref);
        if (now.difference(before).isNotEmpty) return true;
      } on Object catch (error) {
        // Una lettura mancata non chiude l'attesa: si riprova al giro dopo.
        _log.info(
          'rilettura delle tracce di $itemId non riuscita: '
          '${error.runtimeType}',
        );
      }
      if (!ref.mounted) return false;
    }
    return false;
  }

  /// Chiude l'operazione con un avviso: un permesso tolto rilegge l'utente e
  /// dice `noPermission`, il resto è [failure]. Nel log solo l'id e il nome
  /// del fallimento.
  void _fail(Ref ref, Object error, SubtitlesNotice failure) {
    _log.info(
      'sottotitoli di $itemId non riusciti: ${error.runtimeType}'
      '${error is SubtitlesException ? ' ${error.failure.name}' : ''}',
    );
    final forbidden =
        error is SubtitlesException &&
        error.failure == SubtitlesFailure.forbidden;
    // Il notifier della sessione è preso in build: dopo la chiusura della
    // finestra `ref` non si può più usare, ma l'utente va riletto lo stesso.
    if (forbidden) unawaited(_session.refreshUser());
    if (!ref.mounted) return;
    // Un'operazione alla volta: finita male, nessuna resta in corso.
    state = state.copyWith(
      searching: false,
      busyId: null,
      uploading: false,
      notice: forbidden ? SubtitlesNotice.noPermission : failure,
      error: error,
    );
  }
}

final subtitlesControllerProvider = NotifierProvider.autoDispose
    .family<SubtitlesController, SubtitlesState, String>(
      SubtitlesController.new,
    );
