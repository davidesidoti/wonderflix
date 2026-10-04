import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/jellyfin/item_models.dart';
import '../../../core/syncplay/syncplay_models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../library/library_providers.dart';
import '../../mylist/my_list_screen.dart';
import '../../watch_party/party_queue_rules.dart';
import 'queue_add_widgets.dart';
import 'queue_panel_state.dart';
import 'queue_rows.dart';

/// Aggiunge [items] alla coda (in fondo, o con `next` subito dopo); finisce
/// quando l'aggiunta è confermata o fallita.
typedef QueueAddCallback = Future<void> Function(List<JellyfinItem> items,
    {required bool next});

/// La vista Aggiungi (spec H §9.2): il campo "Cerca film e serie" con il
/// focus, La mia lista a campo vuoto, i risultati da 2 lettere. Esc nel
/// campo prima lo svuota, poi chiude il pannello.
class QueueAddView extends ConsumerStatefulWidget {
  const QueueAddView({
    super.key,
    required this.queue,
    required this.focusNode,
    required this.onAdd,
    required this.onOpenSeries,
    required this.onBack,
    required this.onClose,
  });

  final PlayQueue queue;

  /// Il focus del campo: è del player, che sa quando i tasti vanno al campo.
  final FocusNode focusNode;
  final QueueAddCallback onAdd;
  final ValueChanged<JellyfinItem> onOpenSeries;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  ConsumerState<QueueAddView> createState() => _QueueAddViewState();
}

class _QueueAddViewState extends ConsumerState<QueueAddView> {
  // Il testo riparte da quello della ricerca: il pannello sopravvive al
  // cambio di player (spec H §9.1).
  late final _controller =
      TextEditingController(text: ref.read(queueAddSearchProvider).term);

  @override
  void initState() {
    super.initState();
    // `autofocus` non basta dentro il player: si chiede dopo il fotogramma.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _escape() {
    if (_controller.text.isNotEmpty) {
      _controller.clear();
      ref.read(queueAddSearchProvider.notifier).setTerm('');
    } else {
      widget.onClose();
    }
  }

  Widget _row(AppLocalizations l, JellyfinItem item, Set<String> queued,
      bool full) {
    final urls = ref.watch(imageUrlsProvider);
    if (item.kind == ItemKind.series) {
      return QueueItemRow(
        key: ValueKey('queue-add-${item.id}'),
        image: urls.poster(item),
        title: item.name,
        // Le stagioni non si scrivono qui: la ricerca e La mia lista non
        // chiedono `ChildCount`; le conta la vista Serie.
        details: l.partyQueueSeries,
        trailing: const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Icon(LucideIcons.chevronRight,
              size: 18, color: WfColors.creamMuted),
        ),
        onTap: () => widget.onOpenSeries(item),
      );
    }
    return QueueItemRow(
      key: ValueKey('queue-add-${item.id}'),
      image: urls.poster(item),
      title: item.name,
      details: queueRowDetails(l, item),
      trailing: QueueAddButtons(
        queued: queued.contains(item.id),
        full: full,
        onAdd: ({required next}) => widget.onAdd([item], next: next),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final search = ref.watch(queueAddSearchProvider);
    // Sempre osservata, anche mentre si cerca: cercando e tornando a un
    // testo corto La mia lista è già lì, senza una seconda richiesta.
    final favorites = ref.watch(favoritesProvider);
    final queued = partyQueueQueuedIds(widget.queue);
    final full = partyQueueRoom(widget.queue) == 0;
    final searching = search.term.length >= QueueAddSearch.minLength;

    Widget list(String title, List<JellyfinItem> items, String empty) =>
        ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            QueueSectionTitle(title),
            if (items.isEmpty) QueueMessage(text: empty),
            for (final item in items) _row(l, item, queued, full),
          ],
        );

    final Widget body;
    if (searching) {
      final results = search.results;
      body = search.error != null
          ? QueueMessage(
              text: l.partyQueueLoadFailed,
              onRetry: ref.read(queueAddSearchProvider.notifier).retry)
          : results == null
              ? const SizedBox.shrink()
              : list(l.partyQueueResults, results, l.partyQueueNoResults);
    } else {
      body = favorites.when(
            // Ricaricando dopo un cambio sul server resta la lista di prima,
            // come nella pagina La mia lista.
            skipLoadingOnReload: true,
            data: (items) => list(
                l.partyQueueMyList,
                [...items]..sort((a, b) => (a.sortName ?? a.name)
                    .toLowerCase()
                    .compareTo((b.sortName ?? b.name).toLowerCase())),
                l.partyQueueMyListEmpty),
            error: (_, _) => QueueMessage(
                text: l.partyQueueLoadFailed,
                onRetry: () => ref.invalidate(favoritesProvider)),
            loading: () => const SizedBox.shrink(),
          );
    }

    return QueuePanelFrame(
      header: QueuePanelHeader(
        title: l.partyQueueAddTitle,
        onBack: widget.onBack,
        onClose: widget.onClose,
      ),
      field: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: CallbackShortcuts(
          bindings: {
            // Tenuto premuto Esc svuota e basta: senza le ripetizioni non
            // chiude anche il pannello.
            const SingleActivator(LogicalKeyboardKey.escape,
                includeRepeats: false): _escape,
          },
          child: TextField(
            controller: _controller,
            focusNode: widget.focusNode,
            onChanged: ref.read(queueAddSearchProvider.notifier).setTerm,
            // Come nella chat: Invio non toglie il focus al campo (di
            // default "fatto" lo sfoca)...
            onEditingComplete: () {},
            // ...e nemmeno un clic sugli altri pulsanti del pannello. Il
            // campo lo lascia la chiusura del pannello o il cambio di vista.
            onTapOutside: (_) {},
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: l.partyQueueSearchHint,
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              isDense: true,
              filled: true,
              fillColor: WfColors.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: WfColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: WfColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: WfColors.gold),
              ),
            ),
          ),
        ),
      ),
      body: body,
    );
  }
}
