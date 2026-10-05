import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/requests/requests_api.dart';
import '../../core/requests/requests_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'requests_providers.dart';

/// La scheda: tipo, id TMDB e lingua dell'app.
typedef RequestTitleKey = ({RequestMediaType type, int tmdbId, String language});

class RequestTitleState {
  const RequestTitleState({
    this.details,
    this.error,
    this.selected = const {},
    this.sending = false,
  });

  final TitleDetails? details;

  /// Errore del primo caricamento. Con la scheda già caricata un errore di
  /// ricarica non si mostra.
  final Object? error;

  /// Stagioni scelte (solo serie).
  final Set<int> selected;

  /// Una richiesta è in viaggio: Richiedi è bloccato.
  final bool sending;

  RequestTitleState copyWith({Set<int>? selected, bool? sending}) =>
      RequestTitleState(
        details: details,
        error: error,
        selected: selected ?? this.selected,
        sending: sending ?? this.sending,
      );
}

/// Esito di Richiedi, per l'avviso (spec I §9.2).
enum RequestOutcome {
  sent,
  approved,
  alreadyRequested,
  quota,
  account,
  blocklisted,
  noPermission,
  failed,
}

String requestOutcomeText(AppLocalizations l, RequestOutcome outcome) =>
    switch (outcome) {
      RequestOutcome.sent => l.requestsSent,
      RequestOutcome.approved => l.requestsApprovedNow,
      RequestOutcome.alreadyRequested => l.requestsAlreadyRequested,
      RequestOutcome.quota => l.requestsQuota,
      RequestOutcome.account => l.requestsAccount,
      RequestOutcome.blocklisted => l.requestsBlocklisted,
      RequestOutcome.noPermission => l.requestsNoPermission,
      RequestOutcome.failed => l.requestsFailed,
    };

/// La scheda da richiedere (spec I §8.4): carica i dati, tiene le stagioni
/// scelte, manda la richiesta e poi ricarica lo stato da Seerr.
class RequestTitleController extends Notifier<RequestTitleState> {
  RequestTitleController(this.titleKey);

  final RequestTitleKey titleKey;

  /// Numera i caricamenti: vale solo l'ultimo.
  int _loads = 0;

  /// I numeri delle stagioni che si possono ancora chiedere.
  static Set<int> _requestableNumbers(TitleDetails details) => {
        for (final season in details.requestableSeasons) season.seasonNumber,
      };

  @override
  RequestTitleState build() {
    unawaited(Future.microtask(load));
    return const RequestTitleState();
  }

  /// Carica (o ricarica) la scheda. Le stagioni scelte diventano tutte
  /// quelle che si possono ancora chiedere. Il blocco di Richiedi
  /// (`sending`) non lo tocca: lo scioglie solo `submit`.
  Future<void> load() async {
    // Pagina già chiusa (anche prima del microtask di `build`): niente da fare.
    if (!ref.mounted) return;
    final current = ++_loads;
    if (state.details == null && state.error != null) {
      state = const RequestTitleState();
    }
    try {
      final details = await ref.read(requestsApiProvider).title(
          titleKey.type, titleKey.tmdbId,
          language: titleKey.language);
      if (!ref.mounted || current != _loads) return;
      state = RequestTitleState(
        details: details,
        selected: _requestableNumbers(details),
        sending: state.sending,
      );
    } on Object catch (error) {
      if (!ref.mounted || current != _loads) return;
      if (state.details == null) state = RequestTitleState(error: error);
    }
  }

  void toggleSeason(int seasonNumber) {
    final details = state.details;
    if (details == null ||
        state.sending ||
        !details.requestableSeasons.any((s) => s.seasonNumber == seasonNumber)) {
      return;
    }
    final selected = {...state.selected};
    if (!selected.remove(seasonNumber)) selected.add(seasonNumber);
    state = state.copyWith(selected: selected);
  }

  /// "Tutte": sceglie tutte le stagioni da chiedere, o nessuna se lo erano già.
  void toggleAll() {
    final details = state.details;
    if (details == null || state.sending) return;
    final all = _requestableNumbers(details);
    state = state.copyWith(
        selected: state.selected.containsAll(all) ? <int>{} : all);
  }

  /// Torna alla scelta di partenza: tutte le stagioni ancora da chiedere. Il
  /// controller è condiviso e resta vivo con la scheda della libreria: chi
  /// riapre "Richiedi stagioni" non deve ritrovare le caselle tolte l'ultima
  /// volta. Non fa niente durante un invio o senza la scheda.
  void resetSelection() {
    final details = state.details;
    if (details == null || state.sending) return;
    state = state.copyWith(selected: _requestableNumbers(details));
  }

  /// Manda la richiesta: l'esito per l'avviso, `null` se non c'era niente
  /// da mandare o una richiesta era già in viaggio.
  Future<RequestOutcome?> submit() async {
    final details = state.details;
    if (details == null || state.sending || !details.canBeRequested) {
      return null;
    }
    final seasons = details.mediaType == RequestMediaType.tv
        ? (state.selected.toList()..sort())
        : null;
    if (seasons != null && seasons.isEmpty) return null;
    state = state.copyWith(sending: true);
    RequestOutcome outcome;
    try {
      final created = await ref
          .read(requestsApiProvider)
          .create(details.mediaType, details.tmdbId, seasons: seasons);
      outcome = created.status == RequestStatus.pending
          ? RequestOutcome.sent
          : RequestOutcome.approved;
    } on RequestsException catch (error) {
      outcome = switch (error.failure) {
        RequestsFailure.alreadyRequested ||
        RequestsFailure.nothingToRequest =>
          RequestOutcome.alreadyRequested,
        RequestsFailure.quotaExceeded => RequestOutcome.quota,
        RequestsFailure.accountUnavailable => RequestOutcome.account,
        RequestsFailure.blocklisted => RequestOutcome.blocklisted,
        RequestsFailure.noPermission => RequestOutcome.noPermission,
        _ => RequestOutcome.failed,
      };
    } on Object {
      outcome = RequestOutcome.failed;
    }
    if (ref.mounted) {
      // Il nuovo stato (Richiesto, In arrivo) lo dice Seerr. Richiedi resta
      // bloccato finché la ricarica non è finita, così non si può chiedere
      // di nuovo sul vecchio stato della scheda.
      await load();
      if (ref.mounted) state = state.copyWith(sending: false);
    }
    return outcome;
  }
}

final requestTitleControllerProvider = NotifierProvider.autoDispose
    .family<RequestTitleController, RequestTitleState, RequestTitleKey>(
        RequestTitleController.new);
