import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/jellyfin/item_models.dart';
import '../../../core/syncplay/syncplay_models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../library/item_labels.dart';
import '../../watch_party/party_queue_editor.dart';
import '../../watch_party/party_queue_items.dart';
import '../../watch_party/party_queue_rules.dart';
import '../../watch_party/watch_party_session.dart';
import '../player_side_panel_host.dart';
import 'queue_rows.dart';

/// Il pannello "Coda" con i dati del watch party (spec H §9.2): la coda del
/// gruppo, i dettagli dei titoli e i comandi di [PartyQueueEditor].
class PartyQueuePanel extends ConsumerWidget {
  const PartyQueuePanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(
        watchPartySessionProvider.select((s) => s.inGroup ? s.queue : null));
    if (queue == null) return const SizedBox.shrink();
    final editor = ref.read(partyQueueEditorProvider);
    return QueuePanel(
      queue: queue,
      items: ref.watch(partyQueueItemsProvider),
      onJump: (id) => unawaited(editor.jumpTo(id)),
      onRemove: (id) => unawaited(editor.remove(id)),
      onMove: (id, index) => unawaited(editor.move(id, index)),
      onShuffle: (shuffle) => unawaited(editor.setShuffle(shuffle)),
      onClose: onClose,
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

    QueueRow rowFor(PlayQueueEntry entry, QueueRowKind kind, {int? index}) =>
        QueueRow(
          key: ValueKey('party-queue-${entry.playlistItemId}'),
          kind: kind,
          item: widget.items[entry.itemId],
          known: widget.items.containsKey(entry.itemId),
          index: index,
          onTap: kind == QueueRowKind.playing
              ? null
              : () => widget.onJump(entry.playlistItemId),
          onRemove: kind == QueueRowKind.playing
              ? null
              : () => widget.onRemove(entry.playlistItemId),
        );

    final list = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          // Già visti e riga in corso si costruiscono subito, non a
          // richiesta (sono al massimo [partyQueueLimit] righe): una lista
          // pigra non avrebbe ancora la riga in corso quando serve portarla
          // in vista.
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

    return PanelWheelBarrier(
      child: Material(
        color: WfColors.surface.withValues(alpha: 0.94),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: WfColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l.partyQueueTitle,
                          style: WfText.display(24)),
                    ),
                    IconButton(
                      key: const Key('party-queue-shuffle'),
                      icon: const Icon(LucideIcons.shuffle),
                      isSelected: queue.shuffled,
                      tooltip: l.partyQueueShuffle,
                      color: queue.shuffled ? WfColors.gold : WfColors.cream,
                      style: IconButton.styleFrom(
                        backgroundColor: queue.shuffled
                            ? WfColors.gold
                                .withValues(alpha: QueuePanel.shuffleOnFill)
                            : null,
                      ),
                      onPressed: () => widget.onShuffle(!queue.shuffled),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x),
                      tooltip: l.playerClosePanel,
                      color: WfColors.cream,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  runtime == null
                      ? titles
                      : l.partyQueueSummary(titles, formatRuntime(runtime)),
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12),
                ),
              ),
              Expanded(child: list),
            ],
          ),
        ),
      ),
    );
  }
}
