import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/activity_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import 'activity_controller.dart';
import 'admin_providers.dart';
import 'admin_kit.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';

/// La scheda Registro (spec J §9.5): filtri, "Aggiorna" e le voci a pagine.
class ActivityTab extends ConsumerStatefulWidget {
  const ActivityTab({super.key, this.header});

  /// La striscia del server, nel layout stretto: scorre con l'elenco.
  final Widget? header;

  @override
  ConsumerState<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends ConsumerState<ActivityTab> {
  /// Quanto manca alla fine dell'elenco quando si chiede la pagina dopo.
  static const _loadMoreWithin = 600.0;

  final _scroll = SmoothScrollController();

  /// Numero di voci all'ultimo caricamento automatico: evita un ciclo se il
  /// server risponde con pagine vuote.
  int _autoLoadedAt = -1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < _loadMoreWithin) {
        unawaited(ref.read(activityControllerProvider.notifier).loadMore());
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _filterLabel(AppLocalizations l, ActivityFilter filter) =>
      switch (filter) {
        ActivityFilter.all => l.adminActivityAll,
        ActivityFilter.users => l.adminActivityUsers,
        ActivityFilter.system => l.adminActivitySystem,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(activityControllerProvider);
    final controller = ref.read(activityControllerProvider.notifier);

    // Dopo un riavvio di Jellyfin il controller riparte dalla prima pagina
    // (`activity_controller.dart`): come con "Aggiorna", anche la vista
    // torna in cima.
    ref.listen<int>(adminEpochProvider, (_, _) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });

    // Se la prima pagina non riempie la finestra, lo scorrimento non chiede
    // mai la pagina dopo: la si chiede qui.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final current = ref.read(activityControllerProvider);
      if (_scroll.position.maxScrollExtent == 0 &&
          current.hasMore &&
          !current.loading &&
          current.error == null &&
          current.items.length != _autoLoadedAt) {
        _autoLoadedAt = current.items.length;
        unawaited(controller.loadMore());
      }
    });

    final side = adminSideMargin(context);
    final filters = SegmentedButton<ActivityFilter>(
      showSelectedIcon: false,
      segments: [
        for (final filter in ActivityFilter.values)
          ButtonSegment(
              value: filter,
              label: Text(_filterLabel(l, filter),
                  key: ValueKey('activity-filter-${filter.name}'))),
      ],
      selected: {state.filter},
      onSelectionChanged: (selection) =>
          unawaited(controller.setFilter(selection.first)),
    );
    final refresh = TextButton.icon(
      onPressed: () {
        // Si riparte dalla prima pagina: anche la vista torna in
        // cima, non resta a metà di un elenco che cambia.
        if (_scroll.hasClients) _scroll.jumpTo(0);
        unawaited(controller.reload());
      },
      icon: const Icon(LucideIcons.refreshCw, size: 16),
      label: Text(l.adminActivityRefresh),
    );
    // La striscia del server (layout stretto) e il titolo scorrono con
    // l'elenco.
    final header = widget.header;
    final top = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null)
          Padding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 8), child: header),
        Padding(
          padding: EdgeInsets.fromLTRB(side, 0, side, 8),
          child: AdminTabTitle(
              title: l.adminTabActivity, actions: [filters, refresh]),
        ),
      ],
    );
    return _list(l, state, controller, top);
  }

  Widget _list(AppLocalizations l, ActivityState state,
      ActivityController controller, Widget top) {
    final error = state.error;
    if (state.items.isEmpty) {
      final Widget empty;
      if (error != null) {
        empty = ErrorView(
            error: error, onRetry: () => unawaited(controller.reload()));
      } else if (state.loading) {
        empty = const LoadingView();
      } else {
        empty = Padding(
          padding: EdgeInsets.symmetric(horizontal: adminSideMargin(context)),
          child: Text(l.adminActivityEmpty,
              style: const TextStyle(color: WfColors.creamMuted)),
        );
      }
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: top),
          SliverFillRemaining(hasScrollBody: false, child: empty),
        ],
      );
    }
    final now = clock.now();
    final lines = _lines(l, state.items, now);
    return ListView.builder(
      controller: _scroll,
      // Il margine laterale è delle righe, non della lista: la testa
      // (striscia e titolo) ha già il suo.
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: lines.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return top;
        final side = adminSideMargin(context);
        if (index <= lines.length) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: switch (lines[index - 1]) {
              final String day => Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 4),
                  child: Text(day, style: WfText.display(16, color: WfColors.gold)),
                ),
              final ActivityEntry entry => ActivityRow(
                  key: ValueKey('activity-${entry.id}'), entry: entry),
              _ => const SizedBox.shrink(),
            },
          );
        }
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: _footer(l, state, controller),
        );
      },
    );
  }

  /// Le voci con l'intestazione del giorno dove cambia; quelle senza data in
  /// fondo all'ultimo gruppo (senza intestazione se non c'è altro).
  List<Object> _lines(
      AppLocalizations l, List<ActivityEntry> items, DateTime now) {
    final lines = <Object>[];
    String? day;
    for (final entry in items) {
      final date = entry.date;
      if (date == null) continue;
      final label = adminDayLabel(date, now, l);
      if (label != day) lines.add(label);
      day = label;
      lines.add(entry);
    }
    lines.addAll(items.where((entry) => entry.date == null));
    return lines;
  }

  Widget _footer(AppLocalizations l, ActivityState state,
      ActivityController controller) {
    final error = state.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: state.loading
            ? const SizedBox.square(
                dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : error != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(describeError(l, error),
                            style: const TextStyle(color: WfColors.creamMuted)),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                          onPressed: () => unawaited(controller.retry()),
                          child: Text(l.retry)),
                    ],
                  )
                : state.hasMore
                    ? const SizedBox.shrink()
                    : Text(l.adminActivityEnd,
                        style: const TextStyle(color: WfColors.creamMuted)),
      ),
    );
  }
}

/// Il colore del punto di una voce: rosso per avvisi ed errori, oro per le
/// riproduzioni, spento per il resto.
Color activityDotColor(ActivityEntry e) {
  if (e.severity != ActivitySeverity.info) return WfColors.error;
  final type = e.type ?? '';
  if (type.startsWith('VideoPlayback') || type.startsWith('AudioPlayback')) {
    return WfColors.gold;
  }
  return WfColors.creamMuted;
}

/// Una voce del registro: ora (data completa al passaggio del mouse), punto
/// di gravità, testo, dettaglio con un clic e il titolo se c'è.
class ActivityRow extends StatefulWidget {
  const ActivityRow({super.key, required this.entry});

  final ActivityEntry entry;

  @override
  State<ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<ActivityRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = widget.entry;
    final overview = entry.overview;
    final shortOverview = entry.shortOverview;
    final itemId = entry.itemId;
    final date = entry.date;
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    final compact = FormFactor.of(context).compact;
    return InkWell(
      onTap: overview == null ? null : () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: date == null
                  ? null
                  : Tooltip(
                      message: adminFullDateTime(date, l),
                      child: Text(adminHourLabel(date),
                          style: WfText.display(19)),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: DecoratedBox(
                key: Key('activity-severity-${entry.id}-${entry.severity.name}'),
                decoration: BoxDecoration(
                    color: activityDotColor(entry), shape: BoxShape.circle),
                child: const SizedBox.square(dimension: 8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name),
                  if (shortOverview != null) Text(shortOverview, style: muted),
                  if (_expanded && overview != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(overview, style: const TextStyle(fontSize: 13)),
                    ),
                  if (itemId != null)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size(0, compact ? minTouchTarget : 32),
                      ),
                      onPressed: () => openItemById(context, itemId),
                      child: Text(l.adminActivityOpenItem),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
