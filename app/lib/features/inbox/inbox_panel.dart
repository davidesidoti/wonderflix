import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../core/reports/report_models.dart';
import '../../core/social/inbox_models.dart';
import '../../core/social/social_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/panel_header.dart';
import '../../ui/sender_avatar.dart';
import '../../ui/shell_side_panel.dart';
import '../../ui/skeletons.dart';
import '../../ui/bold_spans.dart';
import '../../ui/wf_image.dart';
import '../admin/admin_providers.dart';
import '../library/library_providers.dart';
import '../match/match_actions.dart';
import '../reports/report_labels.dart';
import '../requests/requests_navigation.dart';
import '../watch_party/watch_party_actions.dart';
import '../watch_party/watch_party_directory.dart';
import '../watch_party/watch_party_providers.dart';
import '../watch_party/watch_party_session.dart';
import 'inbox_account_row.dart';
import 'inbox_alert_rows.dart';
import 'inbox_controller.dart';
import 'inbox_groups.dart';
import 'inbox_request_rows.dart';
import 'inbox_row.dart';
import 'inbox_time.dart';
import 'notification_text.dart';

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

/// Contenuto del pannello "Notifiche" (spec G §7.5–7.6): intestazione con
/// Svuota, voci dalla più recente.
class InboxPanel extends ConsumerStatefulWidget {
  const InboxPanel({super.key});

  /// Larghezza: quella dei pannelli laterali.
  static const width = ShellSidePanel.width;

  /// Per quanto resta "Conferma" dopo "Svuota".
  static const clearConfirmFor = Duration(seconds: 4);

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
      focusPanelStart(context, _closeFocus);
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

  /// Per un admin, la vista "Server" invece di "Per te".
  bool _server = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final admin = ref.watch(isAdminProvider);
    final inbox = ref.watch(inboxControllerProvider);
    final all = inbox.snapshot.entries;
    final server = admin && _server;
    final entries = [
      for (final entry in all)
        if (!admin || isServerEntry(entry) == server) entry,
    ];

    Widget viewChip(bool isServer, String label) {
      final count = all
          .where((e) =>
              isServerEntry(e) == isServer && inbox.highlighted.contains(e.id))
          .length;
      return ChoiceChip(
        key: Key(isServer ? 'inbox-view-server' : 'inbox-view-you'),
        selected: server == isServer,
        onSelected: (_) => setState(() => _server = isServer),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Text('$count',
                  style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ],
        ),
      );
    }

    return Material(
      key: const Key('inbox-panel'),
      color: WfColors.surface,
      elevation: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: l.inboxTitle,
            actions: [
              if (entries.isNotEmpty)
                // Con font grandi si stringe (coi puntini) invece di uscire.
                Flexible(
                  child: _ClearButton(
                      // Con l'altra vista vuota si svuota tutto in una
                      // chiamata.
                      ids: entries.length == all.length
                          ? null
                          : [for (final entry in entries) entry.id]),
                ),
            ],
            closeTooltip: l.friendsClose,
            closeFocusNode: _closeFocus,
            onClose: () => ref.read(shellPanelProvider.notifier).close(),
          ),
          if (admin)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  viewChip(false, l.inboxForYou),
                  viewChip(true, l.inboxServer),
                ],
              ),
            ),
          if (server)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(l.inboxServerHint, style: _mutedStyle),
            ),
          Expanded(child: _Entries(entries: entries, server: server)),
        ],
      ),
    );
  }
}

/// "Svuota tutto" → sul posto "Svuota tutto?" e "Sì, svuota" per
/// [InboxPanel.clearConfirmFor] (nell'app non ci sono dialoghi). Con [ids]
/// toglie solo quelle voci, senza svuotare tutta la cassetta.
class _ClearButton extends ConsumerStatefulWidget {
  const _ClearButton({this.ids});

  final List<String>? ids;

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
    final ids = widget.ids;
    final inbox = ref.read(inboxControllerProvider.notifier);
    unawaited(runInboxAction(context,
        () => ids == null ? inbox.clear() : inbox.removeAll(ids)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final confirming = _confirm != null;
    final button = TextButton(
      key: Key(confirming ? 'inbox-clear-confirm' : 'inbox-clear'),
      onPressed: confirming ? _clear : _ask,
      style: TextButton.styleFrom(
        foregroundColor: confirming ? WfColors.error : WfColors.creamMuted,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(confirming ? l.inboxClearConfirm : l.inboxClear,
          maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    if (!confirming) return button;
    // La domanda sopra il bottone: in fila accanto al titolo non ci sta.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(l.inboxClearAsk,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: _mutedStyle),
        ),
        button,
      ],
    );
  }
}

class _Entries extends ConsumerWidget {
  const _Entries({required this.entries, required this.server});

  /// Le voci della vista, dalla più recente.
  final List<InboxEntry> entries;

  /// La vista "Server" di un admin.
  final bool server;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final inbox = ref.watch(inboxControllerProvider);
    if (!inbox.loaded) {
      if (!inbox.failed) return const PanelRowsSkeleton();
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
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(server ? l.inboxServerEmpty : l.inboxEmpty,
            style: _mutedStyle),
      );
    }
    final now = clock.now();
    // Raggruppate con for annidati: l'ordine dentro il gruppo resta quello
    // del plugin (List.sort non è stabile).
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final day in InboxDay.values)
          if (entries.any((e) => inboxDayOf(e.createdAt, now) == day)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                switch (day) {
                  InboxDay.today => l.inboxGroupToday,
                  InboxDay.yesterday => l.inboxGroupYesterday,
                  InboxDay.thisWeek => l.inboxGroupThisWeek,
                  InboxDay.earlier => l.inboxGroupEarlier,
                },
                style: const TextStyle(
                    color: WfColors.creamMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600),
              ),
            ),
            for (final entry in entries)
              if (inboxDayOf(entry.createdAt, now) == day)
                _EntryTile(
                  key: ValueKey('inbox-${entry.id}'),
                  entry: entry,
                  highlighted: inbox.highlighted.contains(entry.id),
                  time: inboxTimeLabel(entry.createdAt, now, l),
                ),
          ],
      ],
    );
  }
}

/// La frase tutta in grassetto (voci senza un nome da evidenziare).
TextSpan _strong(String text) => boldSpans(text, [text]);

/// L'azione a destra della riga ("Unisciti", "Apri").
Widget _rowAction(
        {Key? key, required String label, required VoidCallback? onPressed}) =>
    TextButton(
      key: key,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: WfColors.gold,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );

/// Il testo sotto la frase: il messaggio, la nota, il dettaglio.
Widget _below(String text) =>
    Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: _mutedStyle);

/// Una voce sulla riga comune (spec §7.1): chi la manda, la frase, l'ora e
/// l'azione a destra; la riga intera fa quello che fa l'azione.
class _EntryTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final entry = this.entry;
    void remove() => unawaited(runInboxAction(context,
        () => ref.read(inboxControllerProvider.notifier).remove(entry.id)));

    /// Con [open], "Apri" a destra; la riga e "Apri" chiudono il pannello e
    /// poi vanno dove dice [open].
    InboxRow row({
      required Widget leading,
      required InlineSpan sentence,
      Widget? below,
      void Function()? open,
      Key? openKey,
    }) {
      final onOpen = open == null
          ? null
          : () {
              ref.read(shellPanelProvider.notifier).close();
              open();
            };
      return InboxRow(
        highlighted: highlighted,
        leading: leading,
        sentence: sentence,
        below: below,
        meta: time,
        action: onOpen == null
            ? null
            : _rowAction(label: l.inboxOpen, onPressed: onOpen),
        onOpen: onOpen,
        openKey: openKey,
        onRemove: remove,
      );
    }

    InboxRow alertRow(AlertedEntry entry) {
      final text = notificationTextOf(entry, l);
      return row(
        openKey: Key('inbox-alert-${entry.id}'),
        leading: SystemAvatar(
          icon: alertIconOf(entry),
          alarm: entry is DiskAlmostFullEntry,
          posterItemId: switch (entry) {
            RequestApprovedEntry(:final itemId) ||
            RequestDeclinedEntry(:final itemId) =>
              itemId,
            _ => null,
          },
        ),
        sentence: _strong(text.title),
        below: text.body.isEmpty ? null : _below(text.body),
        open: () => context.go(text.route),
      );
    }

    return switch (entry) {
      InviteEntry() => _InviteRow(
          entry: entry, highlighted: highlighted, time: time, onRemove: remove),
      MatchInviteEntry() => _MatchInviteRow(
          entry: entry, highlighted: highlighted, time: time, onRemove: remove),
      RecommendationEntry() => row(
          openKey: Key('inbox-recommendation-${entry.id}'),
          leading:
              SenderAvatar(name: entry.fromName, posterItemId: entry.itemId),
          sentence: boldSpans(
              l.inboxRecommendation(entry.fromName, entry.title),
              [entry.fromName, entry.title]),
          below: switch (entry.text) {
            final String text => _below(l.inboxRecommendationMessage(text)),
            null => null,
          },
          open: () => openItemById(context, entry.itemId),
        ),
      RequestPendingEntry() => row(
          openKey: Key('inbox-request-${entry.id}'),
          leading: entry.requesterName.trim().isEmpty
              ? const SystemAvatar(icon: LucideIcons.inbox)
              : SenderAvatar(name: entry.requesterName.trim()),
          sentence: boldSpans(
              inboxRequestPendingText(
                  l, entry.requesterName, entry.title, entry.seasons),
              [entry.requesterName.trim(), entry.title]),
          open: () => openRequests(context, tab: RequestsTab.pending),
        ),
      ReportPendingEntry() => row(
          openKey: Key('inbox-report-${entry.id}'),
          leading:
              SenderAvatar(name: entry.fromName, posterItemId: entry.titleId),
          sentence: boldSpans(
              l.inboxReportPending(entry.fromName), [entry.fromName]),
          below: _below(reportTitleLine(l,
              title: entry.title,
              itemType: entry.itemType,
              season: entry.seasonNumber,
              episode: entry.episodeNumber,
              type: entry.reportType)),
          open: _reportOpener(
              context, entry.titleId, entry.itemId, entry.itemType),
        ),
      RequestAvailableEntry() => row(
          openKey: Key('inbox-request-${entry.id}'),
          leading: SystemAvatar(
              icon: LucideIcons.clapperboard, posterItemId: entry.itemId),
          sentence: boldSpans(
              l.inboxRequestAvailable(
                  inboxRequestTitle(l, entry.title, entry.seasons)),
              [entry.title]),
          open: () {
            final itemId = entry.itemId;
            if (itemId != null) {
              openItemById(context, itemId);
            } else {
              // Senza titolo in libreria: le richieste di chi guarda, dove
              // c'è quella arrivata (anche per un admin con altre in attesa).
              openRequests(context, tab: RequestsTab.mine);
            }
          },
        ),
      ReportResolvedEntry() => row(
          openKey: Key('inbox-report-${entry.id}'),
          leading: SystemAvatar(
              icon: entry.outcome == ReportOutcome.fixed
                  ? LucideIcons.circleCheck
                  : LucideIcons.circleAlert,
              posterItemId: entry.titleId),
          sentence: _reportResolvedSentence(l, entry.outcome, entry.title),
          below: switch (entry.text) {
            final String note => _below(l.inboxRecommendationMessage(note)),
            null => null,
          },
          open: _reportOpener(
              context, entry.titleId, entry.itemId, entry.itemType),
        ),
      ContactReminderEntry() => row(
          openKey: Key('inbox-contact-reminder-${entry.id}'),
          leading: const SystemAvatar(icon: LucideIcons.shieldCheck),
          sentence: _strong(l.inboxContactReminderTitle),
          below: _below(inboxContactReminderText(l, entry.channels)),
          open: () => context.go('/settings'),
        ),
      AlertedEntry() => alertRow(entry),
      AnnouncementEntry() => row(
          leading: const SystemAvatar(icon: LucideIcons.megaphone),
          sentence: _strong(l.inboxAnnouncement),
          below: SelectableText(entry.text,
              style: const TextStyle(color: WfColors.cream)),
        ),
      NewTitlesEntry() => row(
          leading: const SystemAvatar(icon: LucideIcons.sparkles),
          sentence: _strong(l.inboxNewTitles(_newTitlesSummary(l, entry))),
          below: _NewTitlesLines(entry: entry),
        ),
    };
  }
}

/// La segnalazione apre il titolo: la stagione segnalata sulla sua scheda,
/// gli altri sulla serie o sul film (piano 24b, decisione 4); senza titolo,
/// niente.
void Function()? _reportOpener(BuildContext context, String? titleId,
        String itemId, ReportItemType? itemType) =>
    titleId == null
        ? null
        : () {
            if (itemType == ReportItemType.season) {
              context.push('/item/$titleId?season=$itemId');
            } else {
              openItemById(context, titleId);
            }
          };

/// "Problema sistemato su **Dark**"; senza titolo, "un titolo".
TextSpan _reportResolvedSentence(
    AppLocalizations l, ReportOutcome outcome, String title) {
  final name = title.isEmpty ? l.inboxReportUnknownTitle : title;
  return boldSpans(
      switch (outcome) {
        ReportOutcome.fixed => l.inboxReportFixed(name),
        ReportOutcome.cannotFix => l.inboxReportCannotFix(name),
      },
      [name]);
}

/// Invito al party (spec §7.1): Unisciti finché il party è nell'elenco e
/// non ci sei; la riga fa lo stesso. Sotto, quanti sono nel party, "Ci sei
/// già" o "Party finito".
class _InviteRow extends ConsumerStatefulWidget {
  const _InviteRow({
    required this.entry,
    required this.highlighted,
    required this.time,
    required this.onRemove,
  });

  final InviteEntry entry;
  final bool highlighted;
  final String time;
  final VoidCallback onRemove;

  @override
  ConsumerState<_InviteRow> createState() => _InviteRowState();
}

class _InviteRowState extends ConsumerState<_InviteRow> {
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
    final current = ref.watch(watchPartySessionProvider
        .select((s) => s.inGroup ? s.group : null));
    final inside =
        current != null && listedGroup([current], entry.groupId) != null;
    // L'invito rende il party visibile finché esiste: se è nell'elenco, si
    // può entrare.
    final group = ref.watch(watchPartyDirectoryProvider
        .select((groups) => listedGroup(groups, entry.groupId)));
    final canJoin = group != null && !inside;
    final join = canJoin && !_joining ? () => unawaited(_join()) : null;
    final String meta;
    if (inside) {
      meta = '${widget.time} · ${l.inboxAlreadyIn}';
    } else if (group == null) {
      meta = '${widget.time} · ${l.inboxPartyEnded}';
    } else if (group.participants.isEmpty) {
      meta = widget.time;
    } else {
      meta = '${widget.time} · ${l.partyMembers(group.participants.length)}';
    }
    return InboxRow(
      highlighted: widget.highlighted,
      leading:
          SenderAvatar(name: entry.fromName, posterItemId: entry.imageItemId),
      sentence: boldSpans(l.notifInviteTitle(entry.fromName, entry.title),
          [entry.fromName, entry.title]),
      meta: meta,
      action: canJoin
          ? _rowAction(
              key: Key('inbox-join-${entry.id}'),
              label: l.watchPartyJoin,
              onPressed: join)
          : null,
      onOpen: join,
      onRemove: widget.onRemove,
    );
  }
}

/// Invito al Match: chi invita e "Unisciti", che apre la sala (spec P §7.2).
/// Il plugin dice se la sala c'è ancora: un no diventa un avviso col motivo.
class _MatchInviteRow extends ConsumerStatefulWidget {
  const _MatchInviteRow({
    required this.entry,
    required this.highlighted,
    required this.time,
    required this.onRemove,
  });

  final MatchInviteEntry entry;
  final bool highlighted;
  final String time;
  final VoidCallback onRemove;

  @override
  ConsumerState<_MatchInviteRow> createState() => _MatchInviteRowState();
}

class _MatchInviteRowState extends ConsumerState<_MatchInviteRow> {
  /// Un ingresso partito da questa voce è in corso (come per i party).
  bool _joining = false;

  Future<void> _join() async {
    if (_joining) return;
    setState(() => _joining = true);
    final panel = ref.read(shellPanelProvider.notifier);
    try {
      final joined = await joinMatchRoom(context, ref, widget.entry.roomId);
      if (joined) panel.close();
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = widget.entry;
    final join = _joining ? null : () => unawaited(_join());
    return InboxRow(
      highlighted: widget.highlighted,
      leading: SenderAvatar(
          name: entry.fromName, badge: LucideIcons.heartHandshake),
      sentence: boldSpans(
          l.notifMatchInviteTitle(entry.fromName), [entry.fromName]),
      meta: widget.time,
      action: _rowAction(
          key: Key('inbox-match-join-${entry.id}'),
          label: l.watchPartyJoin,
          onPressed: join),
      onOpen: join,
      onRemove: widget.onRemove,
    );
  }
}

/// "4 film, 4 episodi".
String _newTitlesSummary(AppLocalizations l, NewTitlesEntry entry) => [
      if (entry.movies.isNotEmpty) l.inboxMovies(entry.movies.length),
      if (entry.episodeCount > 0) l.inboxEpisodes(entry.episodeCount),
    ].join(', ');

/// Le righe delle novità (spec §7.1), con la locandina: le prime 5 e
/// "Mostra tutto". Una riga apre la scheda del film o della serie e chiude
/// il pannello.
class _NewTitlesLines extends ConsumerStatefulWidget {
  const _NewTitlesLines({required this.entry});

  final NewTitlesEntry entry;

  @override
  ConsumerState<_NewTitlesLines> createState() => _NewTitlesLinesState();
}

class _NewTitlesLinesState extends ConsumerState<_NewTitlesLines> {
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
    final urls = ref.watch(imageUrlsProvider);
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
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        width: 24,
                        height: 36,
                        child: WfImage(image: urls.primaryOf(line.id)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(line.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _mutedStyle),
                    ),
                  ],
                ),
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
      ],
    );
  }
}
