import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/display_preferences_api.dart';
import '../library/library_providers.dart';
import 'home_layout.dart';
import 'home_providers.dart';
import 'home_rows_editing.dart';

final _log = Logger('home');

/// Pausa dall'ultima modifica prima di salvare (spec M §8.5): spostando
/// una riga più volte di fila si salva una volta sola.
const homeEditorSaveDelay = Duration(milliseconds: 500);

/// L'elenco di Impostazioni → Home.
@immutable
class HomeUserEditorState {
  const HomeUserEditorState({
    required this.rows,
    required this.hidden,
    required this.stored,
    required this.defaultRows,
    this.saveFailed = false,
  });

  /// Le righe accese dall'admin, nell'ordine dell'utente (spec M §6.4).
  final List<HomeRowKind> rows;

  /// Le righe che l'utente ha nascosto.
  final Set<HomeRowKind> hidden;

  /// La Home dell'utente com'è sul server, con gli id che l'elenco non
  /// mostra.
  final HomeUserPrefs stored;

  /// L'ordine della Home dell'admin, senza ritocchi.
  final List<HomeRowKind> defaultRows;

  /// L'ultimo salvataggio non è riuscito: l'elenco è tornato a [stored].
  final bool saveFailed;

  /// "Ripristina" serve se ci sono ritocchi, salvati o appena fatti.
  bool get canReset =>
      !stored.isEmpty || hidden.isNotEmpty || !listEquals(rows, defaultRows);

  HomeUserEditorState copyWith({
    List<HomeRowKind>? rows,
    Set<HomeRowKind>? hidden,
    HomeUserPrefs? stored,
    bool? saveFailed,
  }) =>
      HomeUserEditorState(
        rows: rows ?? this.rows,
        hidden: hidden ?? this.hidden,
        stored: stored ?? this.stored,
        defaultRows: defaultRows,
        saveFailed: saveFailed ?? this.saveFailed,
      );
}

/// Legge la Home dell'utente e la salva [homeEditorSaveDelay] dopo l'ultima
/// modifica, un salvataggio alla volta: le `DisplayPreferences` si
/// riscrivono intere, e due salvataggi insieme si pesterebbero.
class HomeUserEditor extends AsyncNotifier<HomeUserEditorState> {
  late DisplayPreferencesApi _api;

  /// Mai un id vero: il primo build non è "lo stesso utente" di nessuno.
  String _userId = '';
  List<String>? _adminRows;
  Timer? _timer;

  /// Quello che aspetta i 500 ms.
  HomeUserPrefs? _pending;

  /// L'ultimo salvataggio in coda: il prossimo parte quando finisce. Non
  /// finisce mai con un errore.
  Future<void> _saving = Future.value();

  /// Quanti salvataggi o ripristini sono in coda o in corso.
  var _jobs = 0;

  /// Cresce a ogni salvataggio fallito: quelli già in coda non partono.
  var _failures = 0;

  /// Cresce a ogni "Ripristina": un salvataggio messo in coda prima non
  /// rimette più i suoi ritocchi in `stored`, che da quel momento è `none`.
  var _resets = 0;

  /// Cresce a ogni lettura (build): l'esito di un'operazione partita prima
  /// non tocca più l'elenco, che nel frattempo è stato riletto.
  var _generation = 0;

  /// La Home dell'utente com'è sul server adesso: dove si torna se
  /// un'operazione fallisce.
  var _serverPrefs = HomeUserPrefs.none;

  /// Lascia andare il controller: finché ci sono modifiche da salvare resta
  /// aperto anche se nessuno lo guarda più (si esce dalle Impostazioni).
  void Function()? _release;

  @override
  Future<HomeUserEditorState> build() async {
    final userId = ref.watch(currentUserIdProvider);
    final api = ref.watch(displayPreferencesApiProvider);
    final adminRows = ref.watch(homeAdminRowsProvider.future);
    final generation = ++_generation;
    final sameUser = userId == _userId;
    _userId = userId;
    _api = api;
    ref.onCancel(() {
      // Nessuno guarda più l'elenco: la modifica che aspettava si salva
      // subito, senza i 500 ms.
      if (_pending != null) unawaited(_flush());
    });
    ref.onDispose(() {
      // Se il controller si chiude lo stesso (si ricompone, o si chiude il
      // contenitore) la modifica che aspettava si salva senza più toccare
      // lo stato.
      if (_pending != null) unawaited(_flush());
      _timer?.cancel();
    });
    // Riverpod toglie i blocchi a ogni ricomposizione.
    _release = null;
    if (_jobs > 0) _hold();
    // Rileggendo lo stesso utente si aspetta quello che si sta salvando:
    // senza, si leggerebbe la Home di prima e l'elenco tornerebbe indietro.
    if (sameUser) await _saving;
    // Letta qui e non da `homeUserPrefsProvider`, che una lettura fallita
    // la fa diventare "nessun ritocco": salvando si perderebbero (decisione
    // 9 del piano 19c).
    final stored = await api.readHome(userId);
    final admin = await adminRows;
    if (generation == _generation) {
      _adminRows = admin;
      _serverPrefs = stored;
    }
    return _fromStored(stored);
  }

  HomeUserEditorState _fromStored(HomeUserPrefs stored,
      {bool saveFailed = false}) {
    List<HomeRowKind> order(HomeUserPrefs user) => composeHomeLayout(
            adminRows: _adminRows, user: user, available: (_) => true)
        .order;
    return HomeUserEditorState(
      rows: order(stored),
      hidden: parseHomeRows(stored.hidden).toSet(),
      stored: stored,
      defaultRows: order(HomeUserPrefs.none),
      saveFailed: saveFailed,
    );
  }

  void move(HomeRowKind row, int to) =>
      _edit((state) => state.copyWith(rows: moveRow(state.rows, row, to)));

  void setVisible(HomeRowKind row, bool visible) => _edit((state) =>
      state.copyWith(
          hidden: visible
              ? ({...state.hidden}..remove(row))
              : {...state.hidden, row}));

  void _edit(HomeUserEditorState Function(HomeUserEditorState) change) {
    final current = state.value;
    // Senza la Home letta, o mentre si rilegge (l'elenco che si vede sta per
    // essere sostituito), non si modifica né si salva niente.
    if (current == null || state.isLoading) return;
    final next = change(current).copyWith(saveFailed: false);
    state = AsyncData(next);
    _pending = homeUserPrefsToSave(
        rows: next.rows, hidden: next.hidden, stored: next.stored);
    _hold();
    _timer?.cancel();
    _timer = Timer(homeEditorSaveDelay, () => unawaited(_flush()));
  }

  /// Tiene aperto il controller. Non si può chiamare mentre Riverpod lo
  /// chiude o lo ricompone: lì lo si ritiene da [build].
  void _hold() => _release ??= ref.keepAlive().close;

  /// Se non c'è più niente da salvare, il controller può chiudersi.
  void _releaseIfIdle() {
    if (_jobs > 0 || _pending != null) return;
    final release = _release;
    _release = null;
    if (release != null && ref.mounted) release();
  }

  /// Mette in coda [job], dopo quelli di prima. L'API, l'utente e la lettura
  /// si prendono ora: se il profilo cambia (il controller si ricompone)
  /// prima che parta, la Home è comunque di chi l'ha modificata. Se nel
  /// frattempo uno di quelli di prima è fallito, non parte.
  Future<void> _enqueue(
      Future<void> Function(
              DisplayPreferencesApi api, String userId, int generation)
          job) {
    final api = _api;
    final userId = _userId;
    final generation = _generation;
    final failures = _failures;
    _jobs++;
    return _saving = _saving.then((_) async {
      try {
        if (failures == _failures) await job(api, userId, generation);
      } finally {
        _jobs--;
        _releaseIfIdle();
      }
    });
  }

  /// Mette in coda quello che aspetta.
  Future<void> _flush() {
    _timer?.cancel();
    _timer = null;
    final prefs = _pending;
    _pending = null;
    if (prefs == null) return _saving;
    final resets = _resets;
    return _enqueue((api, userId, generation) =>
        _save(api, userId, generation, resets, prefs));
  }

  Future<void> _save(DisplayPreferencesApi api, String userId, int generation,
      int resets, HomeUserPrefs prefs) async {
    try {
      await api.writeHome(userId, prefs);
    } on Object catch (error) {
      _log.info('Home dell\'utente non salvata: ${error.runtimeType}');
      _failed(userId, generation);
      return;
    }
    if (!ref.mounted) return;
    if (generation == _generation) {
      _serverPrefs = prefs;
      // Dopo un "Ripristina" l'elenco parte dalla Home predefinita: i ritocchi
      // di questo salvataggio, che sta per essere tolto, non tornano in
      // `stored` (e da lì nelle modifiche fatte intanto).
      final current = state.value;
      if (current != null && resets == _resets) {
        state = AsyncData(current.copyWith(stored: prefs));
      }
    }
    // La Home si ricompone con i ritocchi nuovi (spec M §8.5).
    if (userId == _userId) ref.invalidate(homeUserPrefsProvider);
  }

  /// "Ripristina la Home predefinita": toglie le due voci (spec M §6.3),
  /// dopo i salvataggi in coda. L'elenco diventa subito quello predefinito;
  /// se non riesce, torna a com'è sul server. Senza la Home letta non fa
  /// niente.
  Future<void> reset() {
    // Come per le modifiche: senza la Home letta, o mentre si rilegge, no.
    if (state.value == null || state.isLoading) return _saving;
    _resets++;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    state = AsyncData(_fromStored(HomeUserPrefs.none));
    _hold();
    return _enqueue(_reset);
  }

  Future<void> _reset(
      DisplayPreferencesApi api, String userId, int generation) async {
    try {
      await api.resetHome(userId);
    } on Object catch (error) {
      _log.info('Home dell\'utente non ripristinata: ${error.runtimeType}');
      _failed(userId, generation);
      return;
    }
    if (!ref.mounted) return;
    // L'elenco è già quello predefinito, con le modifiche fatte dopo.
    if (generation == _generation) _serverPrefs = HomeUserPrefs.none;
    if (userId == _userId) ref.invalidate(homeUserPrefsProvider);
  }

  /// Un salvataggio o un ripristino non è riuscito: quelli in coda non
  /// partono e l'elenco torna a com'è sul server.
  void _failed(String userId, int generation) {
    // Dopo un cambio di profilo l'esito non riguarda più l'elenco.
    if (userId != _userId) return;
    _failures++;
    if (!ref.mounted || generation != _generation) return;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    state = AsyncData(_fromStored(_serverPrefs, saveFailed: true));
  }
}

final homeUserEditorProvider =
    AsyncNotifierProvider.autoDispose<HomeUserEditor, HomeUserEditorState>(
        HomeUserEditor.new);
