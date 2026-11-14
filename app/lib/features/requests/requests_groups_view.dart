import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_buttons.dart';
import 'request_row.dart';
import 'request_shelf.dart';
import 'requests_list_controller.dart';
import 'requests_navigation.dart';

/// L'elenco di un gruppo di [tab].
RequestsListKey requestsGroupKey(
        RequestsTab tab, RequestsGroup group, String language) =>
    (filter: tab.filter, group: group, language: language);

/// Il pulsante "Richiedi un titolo": apre Cerca (spec §5.2).
class RequestsAskButton extends StatelessWidget {
  const RequestsAskButton({super.key});

  @override
  Widget build(BuildContext context) => WfButton.secondary(
        label: AppLocalizations.of(context).requestsAskTitle,
        icon: LucideIcons.search,
        onPressed: () => context.go('/search'),
      );
}

/// "Le mie" e "Tutte" divise in In corso, Arrivate e Chiuse (spec §5.2,
/// §5.5, §5.7), in un solo `CustomScrollView`.
class RequestsGroupsView extends ConsumerStatefulWidget {
  const RequestsGroupsView(
      {super.key, required this.tab, required this.language});

  final RequestsTab tab;
  final String language;

  @override
  ConsumerState<RequestsGroupsView> createState() => _RequestsGroupsViewState();
}

class _RequestsGroupsViewState extends ConsumerState<RequestsGroupsView> {
  final _scroll = SmoothScrollController();

  /// I tre gruppi hanno avuto la prima risposta: da lì un gruppo che si
  /// ricarica non rimette la pagina in caricamento.
  bool _ready = false;

  /// I gruppi mostrati all'ultimo giro: uno che si ricarica (Riprova, un
  /// avviso) resta al suo posto invece di sparire e far saltare la pagina.
  var _shown = <RequestsGroup>{};

  /// Chiuse si apre al tocco; all'apertura della pagina è chiuso.
  bool _closedOpen = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  RequestsListController _controller(RequestsGroup group) => ref.read(
      requestsListControllerProvider(
              requestsGroupKey(widget.tab, group, widget.language))
          .notifier);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final factor = FormFactor.of(context);
    final narrow = factor.compact && !factor.tv;
    final side = factor.compact ? 16.0 : 32.0;
    final states = {
      for (final group in RequestsGroup.values)
        group: ref.watch(requestsListControllerProvider(
            requestsGroupKey(widget.tab, group, widget.language))),
    };
    _ready = _ready ||
        states.values
            .every((s) => !s.loading || s.items.isNotEmpty || s.error != null);
    if (!_ready) return const LoadingView();
    if (states.values.every((s) => s.items.isEmpty && s.error != null)) {
      _shown = {};
      return ErrorView(
        error: states.values.first.error!,
        onRetry: () {
          for (final group in RequestsGroup.values) {
            unawaited(_controller(group).reload());
          }
        },
      );
    }
    _shown = {
      for (final MapEntry(key: group, value: s) in states.entries)
        if (s.items.isNotEmpty ||
            s.error != null ||
            (s.loading && _shown.contains(group)))
          group,
    };
    if (_shown.isEmpty) {
      if (states.values.any((s) => s.loading)) return const LoadingView();
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: side),
        child: widget.tab == RequestsTab.mine
            ? const _EmptyMine()
            : Text(l.requestsEmptyAll,
                style: const TextStyle(color: WfColors.creamMuted)),
      );
    }

    final now = clock.now();
    final showRequester = widget.tab != RequestsTab.mine;
    final slivers = <Widget>[];
    var first = true;

    void title(String label, RequestsListState state,
        {VoidCallback? onTap, bool? open}) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: first ? 8 : 26, bottom: 6),
          child: _GroupTitle(
              label: label,
              count: state.total ?? (state.error == null ? state.items.length : null),
              size: narrow ? 22 : 24,
              onTap: onTap,
              open: open),
        ),
      ));
      first = false;
    }

    void rows(RequestsListState state) => slivers.add(SliverList.builder(
          itemCount: state.items.length,
          itemBuilder: (context, index) {
            final request = state.items[index];
            return RequestRow(
              key: ValueKey('request-${request.id}'),
              request: request,
              now: now,
              showRequester: showRequester,
              onTap: () => openRequest(context, request),
              separator: index < state.items.length - 1,
            );
          },
        ));

    void footer(RequestsGroup group, RequestsListState state,
        {bool more = false}) {
      final controller = _controller(group);
      // Testo oro senza margine a sinistra; sulla TV con lo spazio per la
      // cornice del fuoco.
      final style = TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.symmetric(horizontal: factor.tv ? 12 : 0, vertical: 6),
          textStyle: const TextStyle(fontWeight: FontWeight.w500));
      final Widget? button;
      if (state.error != null) {
        button = TextButton(
            onPressed: () => unawaited(controller.retry()),
            style: style,
            child: Text(l.retry));
      } else if (state.loading && state.items.isEmpty) {
        // Il gruppo era in errore e si ricarica: Riprova resta, spento.
        button = TextButton(onPressed: null, style: style, child: Text(l.retry));
      } else if (more && state.hasMore) {
        button = TextButton(
          onPressed:
              state.loading ? null : () => unawaited(controller.loadMore()),
          style: style,
          child: Text(l.requestsShowMore),
        );
      } else {
        button = null;
      }
      if (button != null) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            // Sulla TV il pulsante è largo quanto la pagina: scendendo da una
            // locandina a destra il fuoco ci passa, invece di saltarlo.
            child: factor.tv
                ? SizedBox(width: double.infinity, child: button)
                : Align(alignment: Alignment.centerLeft, child: button),
          ),
        ));
      }
    }

    final open = states[RequestsGroup.open]!;
    if (_shown.contains(RequestsGroup.open)) {
      title(l.requestsGroupOpen, open);
      rows(open);
      footer(RequestsGroup.open, open);
    }
    final done = states[RequestsGroup.done]!;
    if (_shown.contains(RequestsGroup.done)) {
      title(l.requestsGroupDone, done);
      if (done.items.isNotEmpty) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: RequestShelf(requests: done.items),
          ),
        ));
      }
      footer(RequestsGroup.done, done, more: true);
    }
    final closed = states[RequestsGroup.closed]!;
    if (_shown.contains(RequestsGroup.closed)) {
      title(l.requestsGroupClosed, closed,
          open: _closedOpen,
          onTap: () => setState(() => _closedOpen = !_closedOpen));
      if (_closedOpen) {
        rows(closed);
        footer(RequestsGroup.closed, closed, more: true);
      }
    }

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        // Larga quanto la finestra (scelta dell'utente dopo la prova).
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, 0, side, 40),
          sliver: SliverMainAxisGroup(slivers: slivers),
        ),
      ],
    );
  }
}

/// Titolo di gruppo in Bebas con il conteggio accanto; con [onTap] anche la
/// freccia (Chiuse).
class _GroupTitle extends StatelessWidget {
  const _GroupTitle({
    required this.label,
    required this.count,
    required this.size,
    this.onTap,
    this.open,
  });

  final String label;
  final int? count;
  final double size;
  final VoidCallback? onTap;
  final bool? open;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    final open = this.open;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label.toUpperCase(), style: WfText.display(size)),
        if (count != null) ...[
          const SizedBox(width: 10),
          Text('$count',
              style: const TextStyle(color: WfColors.creamMuted, fontSize: 13)),
        ],
        if (open != null) ...[
          const SizedBox(width: 4),
          Icon(open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 16, color: WfColors.creamMuted),
        ],
      ],
    );
    if (onTap == null) return Align(alignment: Alignment.centerLeft, child: row);
    return Align(
      alignment: Alignment.centerLeft,
      child: TvFocusable(
        onActivate: onTap,
        child: InkWell(
          onTap: onTap,
          canRequestFocus: !FormFactor.of(context).tv,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: row,
          ),
        ),
      ),
    );
  }
}

/// "Le mie" senza richieste (spec §5.7): invito a cercare e chiedere.
class _EmptyMine extends StatelessWidget {
  const _EmptyMine();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 40, bottom: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.requestsEmptyMineTitle.toUpperCase(),
                style: WfText.display(28)),
            const SizedBox(height: 8),
            Text(l.requestsEmptyMine,
                style: const TextStyle(color: WfColors.creamMuted, fontSize: 14)),
            const SizedBox(height: 18),
            const RequestsAskButton(),
          ],
        ),
      ),
    );
  }
}
