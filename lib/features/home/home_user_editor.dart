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
  late String _userId;
  List<String>? _adminRows;
  Timer? _timer;

  /// Quello che aspetta i 500 ms.
  HomeUserPrefs? _pending;

  /// L'ultimo salvataggio in coda: il prossimo parte quando finisce. Non
  /// finisce mai con un errore.
  Future<void> _saving = Future.value();

  /// Cresce a ogni salvataggio fallito: quelli già in coda non partono.
  var _failures = 0;

  @override
  Future<HomeUserEditorState> build() async {
    _userId = ref.watch(currentUserIdProvider);
    _api = ref.watch(displayPreferencesApiProvider);
    final adminRows = ref.watch(homeAdminRowsProvider.future);
    ref.onDispose(() {
      // Una modifica che aspettava si salva lo stesso, senza più toccare
      // lo stato.
      if (_pending != null) unawaited(_flush());
      _timer?.cancel();
    });
    // Letta qui e non da `homeUserPrefsProvider`, che una lettura fallita
    // la fa diventare "nessun ritocco": salvando si perderebbero (decisione
    // 9 del piano 19c).
    final stored = await _api.readHome(_userId);
    _adminRows = await adminRows;
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
    // Senza la Home letta non si modifica né si salva niente.
    if (current == null) return;
    final next = change(current).copyWith(saveFailed: false);
    state = AsyncData(next);
    _pending = homeUserPrefsToSave(
        rows: next.rows, hidden: next.hidden, stored: next.stored);
    _timer?.cancel();
    _timer = Timer(homeEditorSaveDelay, () => unawaited(_flush()));
  }

  /// Mette in coda quello che aspetta. L'utente e l'API si prendono ora: se
  /// il profilo cambia (il controller si ricompone) prima che il salvataggio
  /// parta, la Home è comunque di chi l'ha modificata.
  Future<void> _flush() {
    _timer?.cancel();
    _timer = null;
    final prefs = _pending;
    _pending = null;
    if (prefs == null) return _saving;
    final api = _api;
    final userId = _userId;
    final failures = _failures;
    return _saving = _saving.then((_) async {
      if (failures == _failures) await _save(api, userId, prefs);
    });
  }

  Future<void> _save(
      DisplayPreferencesApi api, String userId, HomeUserPrefs prefs) async {
    try {
      await api.writeHome(userId, prefs);
    } on Object catch (error) {
      _log.info('Home dell\'utente non salvata: ${error.runtimeType}');
      // Dopo un cambio di profilo l'esito non riguarda più l'elenco.
      if (userId != _userId) return;
      _failures++;
      if (!ref.mounted) return;
      _timer?.cancel();
      _timer = null;
      _pending = null;
      final current = state.value;
      if (current != null) {
        state = AsyncData(_fromStored(current.stored, saveFailed: true));
      }
      return;
    }
    if (!ref.mounted || userId != _userId) return;
    final current = state.value;
    if (current != null) state = AsyncData(current.copyWith(stored: prefs));
    // La Home si ricompone con i ritocchi nuovi (spec M §8.5).
    ref.invalidate(homeUserPrefsProvider);
  }

  /// "Ripristina la Home predefinita": toglie le due voci (spec M §6.3),
  /// dopo i salvataggi in coda.
  Future<void> reset() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    final api = _api;
    final userId = _userId;
    return _saving = _saving.then((_) => _reset(api, userId));
  }

  Future<void> _reset(DisplayPreferencesApi api, String userId) async {
    try {
      await api.resetHome(userId);
    } on Object catch (error) {
      _log.info('Home dell\'utente non ripristinata: ${error.runtimeType}');
      if (!ref.mounted || userId != _userId) return;
      final current = state.value;
      if (current != null) {
        state = AsyncData(current.copyWith(saveFailed: true));
      }
      return;
    }
    if (!ref.mounted || userId != _userId) return;
    state = AsyncData(_fromStored(HomeUserPrefs.none));
    ref.invalidate(homeUserPrefsProvider);
  }
}

final homeUserEditorProvider =
    AsyncNotifierProvider.autoDispose<HomeUserEditor, HomeUserEditorState>(
        HomeUserEditor.new);
