import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/library_providers.dart';
import 'home_data.dart';
import 'home_providers.dart';

final _log = Logger('home');

/// Le serie tolte da "Prossimi episodi" (piano 2026-11-08, Task 1): serie →
/// episodio proposto quando si è tolta, chiavi e valori `jellyfinIdKey`.
/// Stanno nelle `DisplayPreferences` dell'utente e si rileggono al cambio di
/// utente. La serie torna da sola quando Jellyfin propone un altro episodio.
///
/// shortcut: le coppie con un episodio che non è più quello proposto restano
/// salvate; ripulirle se la voce cresce troppo.
class NextUpHidden extends AsyncNotifier<Map<String, String>> {
  /// La scrittura in corso: una alla volta, perché ognuna rilegge e riscrive
  /// l'oggetto intero.
  Future<void> _writes = Future.value();

  /// La lettura all'apertura non è riuscita: prima di scrivere si rilegge,
  /// se no si cancellerebbero le serie già tolte.
  bool _stale = false;
  Future<Map<String, String>>? _reread;

  @override
  Future<Map<String, String>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    _stale = false;
    _reread = null;
    try {
      return await ref
          .watch(displayPreferencesApiProvider)
          .readNextUpHidden(userId);
    } on Object catch (error) {
      _log.info('Prossimi episodi tolti non letti: ${error.runtimeType}');
      _stale = true;
      return const {};
    }
  }

  /// Toglie [seriesId] finché Jellyfin propone [episodeId]; `false` se non si
  /// è salvato (la serie torna).
  Future<bool> hide(String seriesId, String episodeId) =>
      _change(jellyfinIdKey(seriesId), jellyfinIdKey(episodeId));

  /// Rimette [seriesId]; `false` se non si è salvato (resta tolta).
  Future<bool> unhide(String seriesId) =>
      _change(jellyfinIdKey(seriesId), null);

  Future<bool> _change(String series, String? episode) async {
    final api = ref.read(displayPreferencesApiProvider);
    final userId = ref.read(currentUserIdProvider);
    await future;
    if (_stale) {
      // Una sola rilettura anche con più modifiche insieme: la seconda trova
      // nello stato quella della prima.
      try {
        final server = await (_reread ??= api.readNextUpHidden(userId));
        if (_stale) {
          state = AsyncData(server);
          _stale = false;
        }
      } on Object catch (error) {
        _reread = null;
        _log.info('Prossimi episodi tolti non letti: ${error.runtimeType}');
        return false;
      }
    }
    // Lo stato, non `future`: una modifica appena prima è già lì.
    final current = state.value ?? const <String, String>{};
    final before = current[series];
    state = AsyncData(_with(current, series, episode));
    // La mappa si prende quando tocca a questa scrittura: la più recente. Se
    // fallisce si torna indietro prima della scrittura dopo, che se no la
    // manderebbe lo stesso.
    final done = _writes
        .then((_) => api.writeNextUpHidden(userId, state.value ?? const {}))
        .then<bool>((_) => true, onError: (Object error) {
      _log.info('Prossimi episodi non salvati: ${error.runtimeType}');
      if (ref.mounted) {
        state = AsyncData(_with(state.value ?? const {}, series, before));
      }
      return false;
    });
    _writes = done;
    return done;
  }

  static Map<String, String> _with(
    Map<String, String> map,
    String series,
    String? episode,
  ) => episode == null ? ({...map}..remove(series)) : {...map, series: episode};
}

final nextUpHiddenProvider =
    AsyncNotifierProvider<NextUpHidden, Map<String, String>>(NextUpHidden.new);

/// [episode] sta fuori da "Prossimi episodi": la sua serie è stata tolta
/// proprio con questo episodio.
bool hiddenFromNextUp(Map<String, String> hidden, JellyfinItem episode) {
  final seriesId = episode.seriesId;
  return seriesId != null &&
      hidden[jellyfinIdKey(seriesId)] == jellyfinIdKey(episode.id);
}

/// L'episodio di [seriesId] nella riga "Prossimi episodi", chiesto come la
/// Home; `null` se la serie non c'è.
final seriesNextUpProvider = FutureProvider.autoDispose
    .family<JellyfinItem?, String>((ref, seriesId) async {
      ref.watch(libraryRevisionProvider);
      ref.watch(userDataRevisionProvider);
      final next = await ref
          .watch(libraryApiProvider)
          .nextUp(
            ref.watch(currentUserIdProvider),
            seriesId: seriesId,
            limit: 1,
            dateCutoff: nextUpCutoff(clock.now()),
          );
      return next.firstOrNull;
    });

/// Toglie la serie di [episode] da "Prossimi episodi", con la SnackBar
/// "Tolto" e Annulla, o con l'errore.
Future<void> hideFromNextUp(
  BuildContext context,
  WidgetRef ref,
  JellyfinItem episode,
) async {
  final seriesId = episode.seriesId;
  if (seriesId == null) return;
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final hidden = ref.read(nextUpHiddenProvider.notifier);
  final ok = await hidden.hide(seriesId, episode.id);
  messenger?.showSnackBar(
    ok
        ? SnackBar(
            content: Text(l.nextUpHidden),
            action: SnackBarAction(
              label: l.actionUndo,
              onPressed: () =>
                  unawaited(_unhide(hidden, seriesId, messenger, l)),
            ),
          )
        : SnackBar(content: Text(l.nextUpChangeFailed)),
  );
}

/// Rimette [seriesId] in "Prossimi episodi"; se non riesce, la SnackBar.
Future<void> showInNextUp(
  BuildContext context,
  WidgetRef ref,
  String seriesId,
) => _unhide(
  ref.read(nextUpHiddenProvider.notifier),
  seriesId,
  ScaffoldMessenger.maybeOf(context),
  AppLocalizations.of(context),
);

Future<void> _unhide(
  NextUpHidden hidden,
  String seriesId,
  ScaffoldMessengerState? messenger,
  AppLocalizations l,
) async {
  if (!await hidden.unhide(seriesId)) {
    messenger?.showSnackBar(SnackBar(content: Text(l.nextUpChangeFailed)));
  }
}
