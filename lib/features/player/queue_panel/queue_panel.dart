import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/motion.dart';
import '../../../app/theme.dart';
import '../../../core/jellyfin/item_models.dart';
import '../../../core/syncplay/syncplay_models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../ui/wf_buttons.dart';
import '../../library/item_labels.dart';
import '../../watch_party/party_queue_editor.dart';
import '../../watch_party/party_queue_items.dart';
import '../../watch_party/party_queue_rules.dart';
import '../../watch_party/watch_party_session.dart';
import '../player_side_panel_host.dart';
import 'queue_add_view.dart';
import 'queue_add_widgets.dart';
import 'queue_panel_state.dart';
import 'queue_rows.dart';
import 'queue_series_views.dart';

/// Il pannello "Coda" con i dati del watch party (spec H §9.2): sceglie la
/// vista dalla pila di [queuePanelNavProvider] (Coda, Aggiungi, Serie,
/// Stagione) e le dà i dati del gruppo e i comandi di [PartyQueueEditor].
class PartyQueuePanel extends ConsumerWidget {
  const PartyQueuePanel({
    super.key,
    required this.searchFocusNode,
    required this.onClose,
    this.onBeforeJump,
  });

  /// Il focus del campo di ricerca della vista Aggiungi: è del player.
  final FocusNode searchFocusNode;

  final VoidCallback onClose;

  /// Chiamato subito prima del salto su una riga: il player cancella il
  /// `Seek` in sospeso, che non dice l'elemento e il server applicherebbe al
  /// titolo nuovo.
  final VoidCallback? onBeforeJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(
        watchPartySessionProvider.select((s) => s.inGroup ? s.queue : null));
    if (queue == null) return const SizedBox.shrink();
    final editor = ref.read(partyQueueEditorProvider);
    final pages = ref.watch(queuePanelNavProvider);
    final nav = ref.read(queuePanelNavProvider.notifier);
    Future<void> add(List<JellyfinItem> items, {required bool next}) =>
        editor.add(items, next: next);
    final view = switch (pages.last) {
      QueuePanelQueue() => QueuePanel(
          queue: queue,
          items: ref.watch(partyQueueItemsProvider),
          onJump: (id) {
            onBeforeJump?.call();
            unawaited(editor.jumpTo(id));
          },
          onRemove: (id) => unawaited(editor.remove(id)),
          onMove: (id, index) => unawaited(editor.move(id, index)),
          onShuffle: (shuffle) => unawaited(editor.setShuffle(shuffle)),
          onAddTitles: () => nav.open(const QueuePanelAdd()),
          onClose: onClose,
        ),
      QueuePanelAdd() => QueueAddView(
          queue: queue,
          focusNode: searchFocusNode,
          onAdd: add,
          onOpenSeries: (series) => nav.open(QueuePanelSeries(series)),
          onBack: nav.back,
          onClose: onClose,
        ),
      QueuePanelSeries(:final series) => QueueSeriesView(
          series: series,
          queue: queue,
          onAdd: add,
          onOpenSeason: (season) => nav.open(QueuePanelSeason(series, season)),
          onBack: nav.back,
          onClose: onClose,
        ),
      QueuePanelSeason(:final series, :final season) => QueueSeasonView(
          series: series,
          season: season,
          queue: queue,
          onAdd: add,
          onBack: nav.back,
          onClose: onClose,
        ),
    };
    // Le viste si sostituiscono sfumando (spec H §9.2). La chiave è la lista
    // delle viste aperte: ogni navigazione ne dà una nuova, mentre gli
    // aggiornamenti della coda no (la Coda non si rimonta). Una chiave per
    // profondità non basta: lo `AnimatedSwitcher` dà alle uscite la chiave
    // del figlio, e andando e tornando durante la dissolvenza la vista che
    // esce verrebbe riusata come nuova, senza `initState` (il campo non
    // riprenderebbe il focus). Il fondo sta fuori dal cambio: costante, il
    // pannello non si schiarisce a metà.
    return QueuePanelBackdrop(
      child: AnimatedSwitcher(
        duration: WfMotion.of(context).duration(WfMotion.fast),
        child: KeyedSubtree(key: ObjectKey(pages), child: view),
      ),
    );
  }
}

/// La vista Coda (spec H §9.2): intestazione con ordine casuale e ✕,
/// riepilogo, poi "Già visti", "In riproduzione" e "Prossimi"
/// (trascinabili). Non conosce il watch party: riceve la coda, i dettagli e
/// i comandi.
class QueuePanel extends StatefulWidget {
  const QueuePanel({
    super.key,
    required this.queue,
    required this.items,
    required this.onJump,
    required this.onRemove,
    required this.onMove,
    required this.onShuffle,
    required this.onClose,
    this.onAddTitles,
  });

  final PlayQueue queue;

  /// Dettagli per `ItemId`: assente = in arrivo, `null` = non disponibile.
  final Map<String, JellyfinItem?> items;
  final ValueChanged<String> onJump;
  final ValueChanged<String> onRemove;

  /// Un prossimo (id nella coda) portato alla posizione data tra i
  /// prossimi, contata dopo averlo tolto.
  final void Function(String playlistItemId, int upcomingIndex) onMove;
  final ValueChanged<bool> onShuffle;
  final VoidCallback onClose;

  /// "＋ Aggiungi titoli" in fondo (spec H §9.2); `null` = nessun pulsante.
  final VoidCallback? onAddTitles;

  static const width = PlayerSidePanelHost.defaultWidth;

  /// Senza la coda nuova del server entro questo tempo (spostamento non
  /// riuscito), le righe tornano nell'ordine della coda.
  static const pendingTimeout = Duration(seconds: 4);

  /// Dove sta la riga in corso all'apertura (0 = in cima alla lista).
  static const playingAlignment = 0.25;

  /// Fondo del pulsante dell'ordine casuale quando è attivo.
  static const shuffleOnFill = 0.14;

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  final _playingKey = GlobalKey();

  /// Ordine dei prossimi dopo un trascinamento, finché il server non manda
  /// la coda nuova: la riga resta dove la si è lasciata.
  List<String>? _pendingOrder;
  Timer? _pendingTimer;

  /// Id nella coda della riga che si sta trascinando, preso all'inizio del
  /// trascinamento: la coda può cambiare mentre la si trascina, e l'indice
  /// che dà Flutter può non essere più quello della riga.
  String? _draggedId;

  @override
  void initState() {
    super.initState();
    // All'apertura la lista mostra la riga in corso.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final playing = _playingKey.currentContext;
      if (!mounted || playing == null) return;
      unawaited(Scrollable.ensureVisible(playing,
          alignment: QueuePanel.playingAlignment));
    });
  }

  @override
  void didUpdateWidget(QueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // La coda nuova del server vale più dell'ordine provvisorio.
    if (widget.queue.lastUpdate != oldWidget.queue.lastUpdate) _clearPending();
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    super.dispose();
  }

  void _clearPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingOrder = null;
  }

  /// Il trascinamento è finito: la riga è quella presa all'inizio, cercata
  /// nei [upcoming] di adesso (se nel frattempo è sparita non si sposta
  /// niente). [newIndex] è già contato dopo aver tolto la riga
  /// (`onReorderItem`), come lo vuole `MovePlaylistItem`, e si tiene dentro
  /// la lista di adesso.
  void _reorder(List<PlayQueueEntry> upcoming, int newIndex) {
    final moved = _draggedId;
    _draggedId = null;
    if (moved == null) return;
    final oldIndex =
        upcoming.indexWhere((entry) => entry.playlistItemId == moved);
    if (oldIndex < 0) return;
    newIndex = newIndex.clamp(0, upcoming.length - 1);
    if (newIndex == oldIndex) return;
    final order = [for (final entry in upcoming) entry.playlistItemId];
    order.removeAt(oldIndex);
    order.insert(newIndex, moved);
    _pendingTimer?.cancel();
    _pendingTimer = Timer(QueuePanel.pendingTimeout, () {
      if (mounted) setState(_clearPending);
    });
    setState(() => _pendingOrder = order);
    widget.onMove(moved, newIndex);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final queue = widget.queue;
    final sections = partyQueueSections(queue);
    final upcoming = partyQueueInOrder(sections.upcoming, _pendingOrder);
    final runtime = partyQueueUpcomingRuntime(queue, widget.items);
    final titles = l.catalogCount(queue.entries.length);
    final playing = sections.playing;

    QueueRow rowFor(PlayQueueEntry entry, QueueRowKind kind, {int? index}) {
      final item = widget.items[entry.itemId];
      final known = widget.items.containsKey(entry.itemId);
      return QueueRow(
        key: ValueKey('party-queue-${entry.playlistItemId}'),
        kind: kind,
        item: item,
        known: known,
        index: index,
        // Un titolo non disponibile ("Titolo non disponibile") non si apre:
        // resta la ✕ per toglierlo. Con i dettagli ancora in arrivo il
        // clic vale.
        onTap: kind == QueueRowKind.playing || (known && item == null)
            ? null
            : () => widget.onJump(entry.playlistItemId),
        onRemove: kind == QueueRowKind.playing
            ? null
            : () => widget.onRemove(entry.playlistItemId),
      );
    }

    final list = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          // Già visti e riga in corso si costruiscono subito, non a
          // richiesta: una lista pigra non avrebbe ancora la riga in corso
          // quando serve portarla in vista. Sono al massimo
          // [partyQueueLimit] righe, salvo una coda fatta da un altro
          // client (es. Jellyfin web) più lunga: si accetta, è raro.
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sections.watched.isNotEmpty) ...[
                  QueueSectionTitle(l.partyQueueWatched, muted: true),
                  for (final entry in sections.watched)
                    rowFor(entry, QueueRowKind.watched),
                ],
                if (playing != null) ...[
                  QueueSectionTitle(l.partyQueuePlaying),
                  KeyedSubtree(
                      key: _playingKey,
                      child: rowFor(playing, QueueRowKind.playing)),
                ],
                if (upcoming.isNotEmpty)
                  QueueSectionTitle(l.partyQueueUpcoming),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          sliver: SliverReorderableList(
            itemCount: upcoming.length,
            onReorderStart: (index) {
              if (index < upcoming.length) {
                _draggedId = upcoming[index].playlistItemId;
              }
            },
            onReorderItem: (_, newIndex) => _reorder(upcoming, newIndex),
            // Il proxy dà alla riga sollevata fondo e ombra; `QueueRow` ha
            // già il suo `Material` trasparente per l'`InkWell`.
            proxyDecorator: (child, index, animation) => Material(
              color: WfColors.surfaceHigh,
              elevation: 6,
              borderRadius: BorderRadius.circular(QueueRow.radius),
              child: child,
            ),
            itemBuilder: (context, index) =>
                rowFor(upcoming[index], QueueRowKind.upcoming, index: index),
          ),
        ),
      ],
    );

    final onAddTitles = widget.onAddTitles;
    return QueuePanelFrame(
      header: QueuePanelHeader(
        title: l.partyQueueTitle,
        onClose: widget.onClose,
        actions: [
          IconButton(
            key: const Key('party-queue-shuffle'),
            icon: const Icon(LucideIcons.shuffle),
            isSelected: queue.shuffled,
            tooltip: l.partyQueueShuffle,
            color: queue.shuffled ? WfColors.gold : WfColors.cream,
            style: IconButton.styleFrom(
              backgroundColor: queue.shuffled
                  ? WfColors.gold.withValues(alpha: QueuePanel.shuffleOnFill)
                  : null,
            ),
            onPressed: () => widget.onShuffle(!queue.shuffled),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              runtime == null
                  ? titles
                  : l.partyQueueSummary(titles, formatRuntime(runtime)),
              style: const TextStyle(color: WfColors.creamMuted, fontSize: 12),
            ),
          ),
          Expanded(child: list),
        ],
      ),
      footer: onAddTitles == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: WfButton.secondary(
                label: l.partyQueueAddTitles,
                icon: LucideIcons.plus,
                onPressed: onAddTitles,
              ),
            ),
    );
  }
}
