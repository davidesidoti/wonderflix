import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../core/social/inbox_models.dart';
import '../../core/social/social_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/shell_side_panel.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import '../requests/requests_navigation.dart';
import '../watch_party/watch_party_actions.dart';
import '../watch_party/watch_party_directory.dart';
import '../watch_party/watch_party_providers.dart';
import '../watch_party/watch_party_session.dart';
import 'inbox_controller.dart';
import 'inbox_request_rows.dart';
import 'inbox_time.dart';

/// Esegue un'azione sulla cassetta; se non riesce lo dice con una snackbar
/// (spec G §8).
Future<void> runInboxAction(
    BuildContext context, Future<SocialFailure?> Function() action) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failure = await action();
  if (failure == null) return;
  messenger?.showSnackBar(SnackBar(content: Text(l.inboxActionFailed)));
}

const _mutedStyle = TextStyle(color: WfColors.creamMuted, fontSize: 13);
const _timeStyle = TextStyle(color: WfColors.creamMuted, fontSize: 12);

/// Lo stesso gruppo, con o senza trattini e maiuscole.
String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// "{nome} ti invita a guardare" con la prima occorrenza di [name] in
/// grassetto e color crema (spec G §7.6); se il nome non c'è, testo semplice.
TextSpan _inviteFromSpan(String text, String name) {
  final at = name.isEmpty ? -1 : text.indexOf(name);
  if (at < 0) return TextSpan(text: text);
  return TextSpan(children: [
    TextSpan(text: text.substring(0, at)),
    TextSpan(
        text: name,
        style: const TextStyle(
            color: WfColors.cream, fontWeight: FontWeight.w600)),
    TextSpan(text: text.substring(at + name.length)),
  ]);
}

/// Contenuto del pannello "Notifiche" (spec G §7.5–7.6): intestazione con
/// Svuota, voci dalla più recente.
class InboxPanel extends ConsumerStatefulWidget {
  const InboxPanel({super.key});

  /// Larghezza: quella dei pannelli laterali.
  static const width = ShellSidePanel.width;

  /// Per quanto resta "Conferma" dopo "Svuota".
  static const clearConfirmFor = Duration(seconds: 4);

  /// Larghezza della miniatura dell'invito e dell'icona dell'annuncio.
  static const leadingSize = 40.0;

  /// Altezza della miniatura dell'invito (locandina 2:3).
  static const posterHeight = 60.0;

  /// Lato del pallino delle voci non lette.
  static const dotSize = 8.0;

  /// Righe delle novità prima di "Mostra tutto".
  static const newTitlesPreview = 5;

  @override
  ConsumerState<InboxPanel> createState() => _InboxPanelState();
}

class _InboxPanelState extends ConsumerState<InboxPanel> {
  /// Fuoco della × in alto: a pannello aperto la tastiera parte da qui.
  final _closeFocus = FocusNode(debugLabel: 'inbox-close');

  @override
  void initState() {
    super.initState();
    // Come in `FriendsPanel`: `autofocus` non basta, nella shell vera lo
    // scope della pagina ha già un figlio col fuoco (il navigatore annidato)
    // e verrebbe scartato; il fuoco resterebbe sull'icona della barra, sotto
    // lo scuro.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _closeFocus.requestFocus();
      _refreshPartiesForInvites();
    });
  }

  @override
  void dispose() {
    _closeFocus.dispose();
    super.dispose();
  }

  /// "Unisciti" dipende dall'elenco dei party, che si rilegge ogni 30 s: con
  /// degli inviti nella cassetta lo si rilegge all'apertura. Senza accesso ai
  /// watch party non ci sono inviti né elenco.
  void _refreshPartiesForInvites() {
    if (!ref.read(syncPlayAccessProvider).canJoin) return;
    final hasInvites = ref
        .read(inboxControllerProvider)
        .snapshot
        .entries
        .any((entry) => entry is InviteEntry);
    if (hasInvites) {
      unawaited(ref.read(watchPartyDirectoryProvider.notifier).refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hasEntries = ref.watch(
        inboxControllerProvider.select((s) => s.snapshot.entries.isNotEmpty));
    return Material(
      key: const Key('inbox-panel'),
      color: WfColors.surface,
      elevation: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(l.inboxTitle,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                if (hasEntries) const _ClearButton(),
                IconButton(
                  focusNode: _closeFocus,
                  tooltip: l.friendsClose,
                  icon: const Icon(LucideIcons.x, size: 20),
                  onPressed: () =>
                      ref.read(shellPanelProvider.notifier).close(),
                ),
              ],
            ),
          ),
          const Expanded(child: _Entries()),
        ],
      ),
    );
  }
}

/// "Svuota" → "Conferma" per [InboxPanel.clearConfirmFor] (nell'app non ci
/// sono dialoghi).
class _ClearButton extends ConsumerStatefulWidget {
  const _ClearButton();

  @override
  ConsumerState<_ClearButton> createState() => _ClearButtonState();
}

class _ClearButtonState extends ConsumerState<_ClearButton> {
  Timer? _confirm;

  @override
  void dispose() {
    _confirm?.cancel();
    super.dispose();
  }

  void _ask() {
    _confirm?.cancel();
    setState(() {
      _confirm = Timer(InboxPanel.clearConfirmFor, () {
        if (mounted) setState(() => _confirm = null);
      });
    });
  }

  void _clear() {
    _confirm?.cancel();
    setState(() => _confirm = null);
    unawaited(runInboxAction(
        context, () => ref.read(inboxControllerProvider.notifier).clear()));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final confirming = _confirm != null;
    return TextButton(
      key: Key(confirming ? 'inbox-clear-confirm' : 'inbox-clear'),
      onPressed: confirming ? _clear : _ask,
      style: TextButton.styleFrom(
        foregroundColor: confirming ? WfColors.error : WfColors.creamMuted,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(confirming ? l.inboxClearConfirm : l.inboxClear),
    );
  }
}

class _Entries extends ConsumerWidget {
  const _Entries();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final inbox = ref.watch(inboxControllerProvider);
    if (!inbox.loaded) {
      // Mentre carica la prima volta il pannello resta vuoto.
      if (!inbox.failed) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.inboxUnavailable, style: _mutedStyle),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => unawaited(
                  ref.read(inboxControllerProvider.notifier).reload()),
              style: TextButton.styleFrom(
                foregroundColor: WfColors.gold,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(l.retry),
            ),
          ],
        ),
      );
    }
    final entries = inbox.snapshot.entries;
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(l.inboxEmpty, style: _mutedStyle),
      );
    }
    final now = clock.now();
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final entry in entries)
          _EntryTile(
            key: ValueKey('inbox-${entry.id}'),
            entry: entry,
            highlighted: inbox.highlighted.contains(entry.id),
            time: inboxTimeLabel(entry.createdAt, now, l),
          ),
      ],
    );
  }
}

/// Una voce: pallino (se evidenziata), miniatura o icona, contenuto, ×
/// (visibile al passaggio del mouse e col fuoco).
class _EntryTile extends ConsumerStatefulWidget {
  const _EntryTile({
    super.key,
    required this.entry,
    required this.highlighted,
    required this.time,
  });

  final InboxEntry entry;
  final bool highlighted;
  final String time;

  @override
  ConsumerState<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends ConsumerState<_EntryTile> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = widget.entry;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: InboxPanel.dotSize,
              child: widget.highlighted
                  ? Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        key: Key('inbox-unread-${entry.id}'),
                        width: InboxPanel.dotSize,
                        height: InboxPanel.dotSize,
                        decoration: const BoxDecoration(
                            color: WfColors.gold, shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            switch (entry) {
              InviteEntry() => _InvitePoster(entry: entry),
              AnnouncementEntry() => const _AnnouncementIcon(),
              NewTitlesEntry() => const _NewTitlesIcon(),
              RequestAvailableEntry() => const InboxRequestIcon(
                  icon: LucideIcons.clapperboard, size: InboxPanel.leadingSize),
              RequestPendingEntry() => const InboxRequestIcon(
                  icon: LucideIcons.inbox, size: InboxPanel.leadingSize),
            },
            const SizedBox(width: 12),
            Expanded(
              child: switch (entry) {
                InviteEntry() =>
                  _InviteContent(entry: entry, time: widget.time),
                AnnouncementEntry() =>
                  _AnnouncementContent(entry: entry, time: widget.time),
                NewTitlesEntry() =>
                  _NewTitlesContent(entry: entry, time: widget.time),
                RequestAvailableEntry() => InboxRequestContent(
                    key: Key('inbox-request-${entry.id}'),
                    text: l.inboxRequestAvailable(
                        inboxRequestTitle(l, entry.title, entry.seasons)),
                    time: widget.time,
                    onOpen: () {
                      final itemId = entry.itemId;
                      if (itemId != null) {
                        openItemById(context, itemId);
                      } else {
                        openRequests(context);
                      }
                    },
                  ),
                RequestPendingEntry() => InboxRequestContent(
                    key: Key('inbox-request-${entry.id}'),
                    text: l.inboxRequestPending(entry.requesterName,
                        inboxRequestTitle(l, entry.title, entry.seasons)),
                    time: widget.time,
                    onOpen: () => openRequests(context, tab: RequestsTab.pending),
                  ),
              },
            ),
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (focused) => setState(() => _focused = focused),
              child: Opacity(
                opacity: _hovered || _focused ? 1 : 0,
                // Nascosta resta per i lettori di schermo.
                alwaysIncludeSemantics: true,
                child: IconButton(
                  tooltip: l.inboxRemove,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(LucideIcons.x,
                      size: 16, color: WfColors.creamMuted),
                  onPressed: () => unawaited(runInboxAction(
                      context,
                      () => ref
                          .read(inboxControllerProvider.notifier)
                          .remove(entry.id))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitePoster extends ConsumerWidget {
  const _InvitePoster({required this.entry});

  final InviteEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageId = entry.imageItemId;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: InboxPanel.leadingSize,
        height: InboxPanel.posterHeight,
        child: WfImage(
          image: imageId == null
              ? null
              : ref.watch(imageUrlsProvider).primaryOf(imageId),
        ),
      ),
    );
  }
}

class _AnnouncementIcon extends StatelessWidget {
  const _AnnouncementIcon();

  @override
  Widget build(BuildContext context) => Container(
        width: InboxPanel.leadingSize,
        height: InboxPanel.leadingSize,
        decoration: const BoxDecoration(
            color: WfColors.surfaceHigh, shape: BoxShape.circle),
        child: const Icon(LucideIcons.megaphone,
            size: 18, color: WfColors.gold),
      );
}

class _NewTitlesIcon extends StatelessWidget {
  const _NewTitlesIcon();

  @override
  Widget build(BuildContext context) => Container(
        width: InboxPanel.leadingSize,
        height: InboxPanel.leadingSize,
        decoration: const BoxDecoration(
            color: WfColors.surfaceHigh, shape: BoxShape.circle),
        child: const Icon(LucideIcons.sparkles,
            size: 18, color: WfColors.gold),
      );
}

/// Invito: chi, cosa e Unisciti finché il party c'è (spec G §7.6).
class _InviteContent extends ConsumerStatefulWidget {
  const _InviteContent({required this.entry, required this.time});

  final InviteEntry entry;
  final String time;

  @override
  ConsumerState<_InviteContent> createState() => _InviteContentState();
}

class _InviteContentState extends ConsumerState<_InviteContent> {
  /// Un ingresso partito da questa voce è in corso: un secondo clic non deve
  /// farne un altro (la sessione, già "in ingresso", risponderebbe subito di
  /// sì e il pannello si chiuderebbe prima dell'esito vero).
  bool _joining = false;

  /// Entra nel party; riuscito, il pannello si chiude.
  Future<void> _join() async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
      final joined = await joinWatchParty(context, ref, widget.entry.groupId);
      if (!mounted) return;
      if (joined) {
        ref.read(shellPanelProvider.notifier).close();
      } else {
        // Non riuscito: l'elenco può essere vecchio (il party è finito).
        unawaited(ref.read(watchPartyDirectoryProvider.notifier).refresh());
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = widget.entry;
    final groupId = _normalizeId(entry.groupId);
    final inGroupId = ref.watch(watchPartySessionProvider
        .select((s) => s.inGroup ? s.group?.id : null));
    // L'invito rende il party visibile finché esiste: se è nell'elenco, si
    // può entrare.
    final listed = ref.watch(watchPartyDirectoryProvider
        .select((groups) => groups.any((g) => _normalizeId(g.id) == groupId)));
    final Widget action;
    if (inGroupId != null && _normalizeId(inGroupId) == groupId) {
      action = Text(l.inboxAlreadyIn,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: _mutedStyle);
    } else if (listed) {
      action = TextButton(
        key: Key('inbox-join-${entry.id}'),
        onPressed: _joining ? null : () => unawaited(_join()),
        style: TextButton.styleFrom(
          foregroundColor: WfColors.gold,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(l.watchPartyJoin),
      );
    } else {
      action = Text(l.inboxPartyEnded,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: _mutedStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Il nome di chi invita in evidenza (spec G §7.6).
        Text.rich(
            _inviteFromSpan(l.inboxInviteFrom(entry.fromName), entry.fromName),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _mutedStyle),
        Text(entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: WfColors.cream, fontWeight: FontWeight.w600)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // L'ora e lo stato si dividono lo spazio (testi lunghi, font
            // grandi), lo stato ne ha di più; l'azione resta a destra.
            Flexible(
              child: Text(widget.time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _timeStyle),
            ),
            Flexible(flex: 2, child: action),
          ],
        ),
      ],
    );
  }
}

/// Annuncio dell'admin: etichetta e testo intero, selezionabile.
class _AnnouncementContent extends StatelessWidget {
  const _AnnouncementContent({required this.entry, required this.time});

  final AnnouncementEntry entry;
  final String time;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.inboxAnnouncement,
            style: const TextStyle(
                color: WfColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        SelectableText(entry.text,
            style: const TextStyle(color: WfColors.cream)),
        const SizedBox(height: 4),
        Text(time, style: _timeStyle),
      ],
    );
  }
}

/// Novità (spec G §7.6): riepilogo, le prime righe e "Mostra tutto". Una
/// riga apre la scheda del film o della serie e chiude il pannello.
class _NewTitlesContent extends ConsumerStatefulWidget {
  const _NewTitlesContent({required this.entry, required this.time});

  final NewTitlesEntry entry;
  final String time;

  @override
  ConsumerState<_NewTitlesContent> createState() => _NewTitlesContentState();
}

class _NewTitlesContentState extends ConsumerState<_NewTitlesContent> {
  bool _expanded = false;

  /// Fuoco della prima riga svelata da "Mostra tutto": il bottone sparisce e
  /// il fuoco da tastiera non deve andare perso.
  final _firstRevealed = FocusNode(debugLabel: 'inbox-first-revealed-title');

  @override
  void dispose() {
    _firstRevealed.dispose();
    super.dispose();
  }

  void _open(String itemId) {
    ref.read(shellPanelProvider.notifier).close();
    openItemById(context, itemId);
  }

  void _showAll() {
    setState(() => _expanded = true);
    // La riga esiste solo dopo il rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstRevealed.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = widget.entry;
    final summary = [
      if (entry.movies.isNotEmpty) l.inboxMovies(entry.movies.length),
      if (entry.episodeCount > 0) l.inboxEpisodes(entry.episodeCount),
    ].join(', ');
    final lines = [
      for (final movie in entry.movies)
        (
          id: movie.itemId,
          text: movie.year == null
              ? movie.name
              : '${movie.name} (${movie.year})',
        ),
      for (final series in entry.series)
        (
          id: series.seriesId,
          text: '${series.name} · '
              '${formatEpisodeRanges(series.episodes) ?? l.inboxNewEpisodes(series.episodes.length)}',
        ),
    ];
    final shown = _expanded
        ? lines
        : lines.take(InboxPanel.newTitlesPreview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.inboxNewTitles(summary),
            style: const TextStyle(
                color: WfColors.cream, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        for (final (index, line) in shown.indexed)
          // Largo quanto il pannello: si tocca anche a destra del titolo.
          SizedBox(
            width: double.infinity,
            child: InkWell(
              key: Key('inbox-title-${line.id}'),
              focusNode:
                  index == InboxPanel.newTitlesPreview ? _firstRevealed : null,
              onTap: () => _open(line.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(line.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _mutedStyle),
              ),
            ),
          ),
        if (!_expanded && lines.length > InboxPanel.newTitlesPreview)
          TextButton(
            onPressed: _showAll,
            style: TextButton.styleFrom(
              foregroundColor: WfColors.gold,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            child: Text(l.inboxShowAll(lines.length)),
          ),
        if (entry.more > 0) Text(l.inboxMore(entry.more), style: _mutedStyle),
        const SizedBox(height: 4),
        Text(widget.time, style: _timeStyle),
      ],
    );
  }
}
