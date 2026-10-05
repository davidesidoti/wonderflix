import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import 'approve_dialog.dart';
import 'pending_request_actions.dart';
import 'request_row.dart';
import 'requests_list_controller.dart';
import 'requests_navigation.dart';
import 'requests_providers.dart';

/// La pagina Richieste (spec I §9.4): "Le mie" e, per chi può approvare,
/// "Da approvare (n)" e "Tutte". La scheda sta nell'indirizzo (`?tab=`): i
/// pulsanti delle schede cambiano l'indirizzo, e la rotta rifà la pagina a
/// ogni indirizzo nuovo. Senza una scheda nell'indirizzo si apre su "Da
/// approvare" se c'è qualcosa da approvare, altrimenti su "Le mie", e la
/// scelta resta quella.
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key, this.initialTab});

  /// La scheda dell'indirizzo (`?tab=`), se c'è.
  final RequestsTab? initialTab;

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  /// Dove va la pagina quando le richieste spariscono: la Home.
  static const _homeRoute = '/home';

  /// Già partita verso la Home: la pagina ci va una volta sola.
  bool _leaving = false;

  /// La scheda scelta da sola, una volta, quando l'indirizzo non ne ha una:
  /// approvare l'ultima richiesta o riceverne una nuova non sposta la pagina.
  RequestsTab? _auto;

  @override
  Widget build(BuildContext context) {
    // Seerr tolto dal plugin mentre si guarda la pagina (o aperta senza la
    // funzione): la voce nella barra è sparita, e le chiamate darebbero 503.
    // Si torna alla Home, senza mostrare l'errore.
    if (ref.watch(requestsGoneProvider)) {
      if (!_leaving) {
        _leaving = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(_homeRoute);
        });
      }
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final me = ref.watch(requestsMeProvider);
    final canManage = me.value?.canManage ?? false;
    final count = canManage ? ref.watch(pendingRequestsCountProvider(language)) : null;
    final explicit = widget.initialTab;
    // Per scegliere da sola la scheda la pagina aspetta i permessi e, per
    // chi approva, il conteggio.
    final ready = (me.hasValue || me.hasError) &&
        (count == null || count.hasValue || count.hasError || explicit != null);
    final tabs = [
      RequestsTab.mine,
      if (canManage) ...[RequestsTab.pending, RequestsTab.all],
    ];
    final pendingCount = count?.value;
    if (ready && explicit == null) {
      _auto ??= (pendingCount?.count ?? 0) > 0
          ? RequestsTab.pending
          : RequestsTab.mine;
    }
    var tab = explicit ?? _auto ?? RequestsTab.mine;
    if (!tabs.contains(tab)) tab = RequestsTab.mine;

    String tabLabel(RequestsTab tab) => switch (tab) {
          RequestsTab.mine => l.requestsTabMine,
          RequestsTab.pending => pendingCount == null
              ? l.requestsTabPending
              : l.requestsTabPendingCount(pendingCountLabel(pendingCount)),
          RequestsTab.all => l.requestsTabAll,
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
          child: Text(l.navRequests.toUpperCase(), style: WfText.display(40)),
        ),
        if (!ready)
          const Expanded(child: LoadingView())
        else ...[
          if (tabs.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  for (final item in tabs) ...[
                    _TabButton(
                      key: ValueKey('requests-tab-${item.name}'),
                      label: tabLabel(item),
                      selected: item == tab,
                      onTap: () => openRequests(context, tab: item),
                    ),
                    const SizedBox(width: 24),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _RequestsList(
              key: ValueKey(tab),
              tab: tab,
              listKey: (filter: tab.filter, language: language),
            ),
          ),
        ],
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: selected ? WfColors.gold : Colors.transparent, width: 2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? WfColors.cream : WfColors.creamMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _RequestsList extends ConsumerStatefulWidget {
  const _RequestsList({super.key, required this.tab, required this.listKey});

  final RequestsTab tab;
  final RequestsListKey listKey;

  @override
  ConsumerState<_RequestsList> createState() => _RequestsListState();
}

class _RequestsListState extends ConsumerState<_RequestsList> {
  /// Quanto manca alla fine dell'elenco quando si chiede la pagina dopo.
  static const _loadMoreWithin = 600.0;

  final _scroll = SmoothScrollController();

  /// Numero di righe al momento dell'ultimo caricamento automatico: evita
  /// un ciclo infinito se il server risponde con pagine vuote.
  int _autoLoadedAt = -1;

  /// Le righe all'ultimo controllo: se l'elenco si accorcia (un
  /// ricaricamento, una riga tolta) il caricamento automatico può ripartire.
  int _lastLength = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < _loadMoreWithin) {
        unawaited(ref
            .read(requestsListControllerProvider(widget.listKey).notifier)
            .loadMore());
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _approve(MediaRequest request) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showApproveDialog(context, request);
    if (choice == null || !mounted) return;
    final outcome = await ref
        .read(requestsListControllerProvider(widget.listKey).notifier)
        .approve(request.id, choice);
    if (outcome != null) {
      messenger.showSnackBar(SnackBar(content: Text(requestActionText(l, outcome))));
    }
  }

  Future<void> _decline(MediaRequest request) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref
        .read(requestsListControllerProvider(widget.listKey).notifier)
        .decline(request.id);
    if (outcome != null) {
      messenger.showSnackBar(SnackBar(content: Text(requestActionText(l, outcome))));
    }
  }

  String _emptyText(AppLocalizations l) => switch (widget.tab) {
        RequestsTab.mine => l.requestsEmptyMine,
        RequestsTab.pending => l.requestsEmptyPending,
        RequestsTab.all => l.requestsEmptyAll,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final provider = requestsListControllerProvider(widget.listKey);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final error = state.error;

    // Su schermi grandi le prime righe possono non riempire la finestra:
    // senza scroll non scatterebbe mai il caricamento successivo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(provider);
      // Un elenco più corto di prima è ripartito: una pagina vuota, invece,
      // lascia la lunghezza com'è e il ciclo resta fermo.
      if (current.items.length < _lastLength) _autoLoadedAt = -1;
      _lastLength = current.items.length;
      if (!_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent == 0 &&
          current.hasMore &&
          !current.loading &&
          current.error == null &&
          current.items.length != _autoLoadedAt) {
        _autoLoadedAt = current.items.length;
        unawaited(ref.read(provider.notifier).loadMore());
      }
    });

    if (state.items.isEmpty) {
      if (error != null) {
        return ErrorView(error: error, onRetry: () => unawaited(controller.reload()));
      }
      if (state.loading) return const LoadingView();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(_emptyText(l), style: const TextStyle(color: WfColors.creamMuted)),
      );
    }
    final now = clock.now();
    final footer = state.loading || error != null;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
      itemCount: state.items.length + (footer ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: error != null
                  ? TextButton(
                      onPressed: () => unawaited(controller.retry()),
                      child: Text(l.retry))
                  : const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }
        final request = state.items[index];
        return RequestRow(
          key: ValueKey('request-${request.id}'),
          request: request,
          now: now,
          showRequester: widget.tab != RequestsTab.mine,
          // Con Approva o Rifiuta in viaggio la riga non apre niente.
          onTap: state.busy.contains(request.id)
              ? null
              : () => openRequest(context, request),
          trailing: widget.tab == RequestsTab.pending
              ? PendingRequestActions(
                  busy: state.busy.contains(request.id),
                  onApprove: () => unawaited(_approve(request)),
                  onDecline: () => unawaited(_decline(request)),
                )
              : null,
        );
      },
    );
  }
}
