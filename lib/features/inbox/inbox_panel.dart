import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../core/social/inbox_models.dart';
import '../../core/social/social_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/shell_side_panel.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import '../watch_party/watch_party_actions.dart';
import '../watch_party/watch_party_directory.dart';
import '../watch_party/watch_party_session.dart';
import 'inbox_controller.dart';
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

/// Contenuto del pannello "Notifiche" (spec G §7.5–7.6): intestazione con
/// Svuota, voci dalla più recente.
class InboxPanel extends ConsumerWidget {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            },
            const SizedBox(width: 12),
            Expanded(
              child: switch (entry) {
                InviteEntry() =>
                  _InviteContent(entry: entry, time: widget.time),
                AnnouncementEntry() =>
                  _AnnouncementContent(entry: entry, time: widget.time),
              },
            ),
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (focused) => setState(() => _focused = focused),
              child: Opacity(
                opacity: _hovered || _focused ? 1 : 0,
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

/// Invito: chi, cosa e Unisciti finché il party c'è (spec G §7.6).
class _InviteContent extends ConsumerWidget {
  const _InviteContent({required this.entry, required this.time});

  final InviteEntry entry;
  final String time;

  /// Entra nel party; riuscito, il pannello si chiude.
  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final joined = await joinWatchParty(context, ref, entry.groupId);
    if (joined && context.mounted) {
      ref.read(shellPanelProvider.notifier).close();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final groupId = _normalizeId(entry.groupId);
    final inGroupId = ref.watch(watchPartySessionProvider
        .select((s) => s.inGroup ? s.group?.id : null));
    // L'invito rende il party visibile finché esiste: se è nell'elenco, si
    // può entrare.
    final listed = ref.watch(watchPartyDirectoryProvider
        .select((groups) => groups.any((g) => _normalizeId(g.id) == groupId)));
    final Widget action;
    if (inGroupId != null && _normalizeId(inGroupId) == groupId) {
      action = Text(l.inboxAlreadyIn, style: _mutedStyle);
    } else if (listed) {
      action = TextButton(
        key: Key('inbox-join-${entry.id}'),
        onPressed: () => unawaited(_join(context, ref)),
        style: TextButton.styleFrom(
          foregroundColor: WfColors.gold,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(l.watchPartyJoin),
      );
    } else {
      action = Text(l.inboxPartyEnded, style: _mutedStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.inboxInviteFrom(entry.fromName),
            maxLines: 2, overflow: TextOverflow.ellipsis, style: _mutedStyle),
        Text(entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: WfColors.cream, fontWeight: FontWeight.w600)),
        Row(
          children: [
            // L'ora cede lo spazio all'azione (testi lunghi, font grandi).
            Expanded(
              child: Text(time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _timeStyle),
            ),
            action,
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
