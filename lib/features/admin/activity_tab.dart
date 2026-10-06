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
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import 'activity_controller.dart';
import 'admin_time.dart';

/// La scheda Registro (spec J §9.5): filtri, "Aggiorna" e le voci a pagine.
class ActivityTab extends ConsumerStatefulWidget {
  const ActivityTab({super.key});

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
          child: Row(
            children: [
              for (final filter in ActivityFilter.values) ...[
                ChoiceChip(
                  key: ValueKey('activity-filter-${filter.name}'),
                  label: Text(_filterLabel(l, filter)),
                  selected: filter == state.filter,
                  onSelected: (_) => unawaited(controller.setFilter(filter)),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  // Si riparte dalla prima pagina: anche la vista torna in
                  // cima, non resta a metà di un elenco che cambia.
                  if (_scroll.hasClients) _scroll.jumpTo(0);
                  unawaited(controller.reload());
                },
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: Text(l.adminActivityRefresh),
              ),
            ],
          ),
        ),
        Expanded(child: _list(l, state, controller)),
      ],
    );
  }

  Widget _list(
      AppLocalizations l, ActivityState state, ActivityController controller) {
    final error = state.error;
    if (state.items.isEmpty) {
      if (error != null) {
        return ErrorView(
            error: error, onRetry: () => unawaited(controller.reload()));
      }
      if (state.loading) return const LoadingView();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(l.adminActivityEmpty,
            style: const TextStyle(color: WfColors.creamMuted)),
      );
    }
    final now = clock.now();
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
      itemCount: state.items.length + 1,
      itemBuilder: (context, index) {
        if (index < state.items.length) {
          final entry = state.items[index];
          return ActivityRow(
              key: ValueKey('activity-${entry.id}'), entry: entry, now: now);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: state.loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : error != null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(describeError(l, error),
                                style:
                                    const TextStyle(color: WfColors.creamMuted)),
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
      },
    );
  }
}

/// Una voce del registro: gravità, testo, dettaglio con un clic, il titolo
/// se c'è e l'ora (data completa al passaggio del mouse).
class ActivityRow extends StatefulWidget {
  const ActivityRow({super.key, required this.entry, required this.now});

  final ActivityEntry entry;
  final DateTime now;

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
    final (icon, color) = switch (entry.severity) {
      ActivitySeverity.info => (LucideIcons.info, WfColors.creamMuted),
      ActivitySeverity.warning => (LucideIcons.triangleAlert, WfColors.gold),
      ActivitySeverity.error => (LucideIcons.circleX, WfColors.error),
    };
    return InkWell(
      onTap: overview == null ? null : () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                key: Key('activity-severity-${entry.id}-${entry.severity.name}'),
                size: 18,
                color: color),
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
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: () => openItemById(context, itemId),
                      child: Text(l.adminActivityOpenItem),
                    ),
                ],
              ),
            ),
            if (date != null) ...[
              const SizedBox(width: 12),
              Tooltip(
                message: adminFullDateTime(date, l),
                child: Text(adminTimeLabel(date, widget.now, l), style: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
