import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';
import 'party_notices.dart';

String partyNoticeText(AppLocalizations l, PartyNotice notice) {
  final time = formatClock(notice.position ?? Duration.zero);
  return switch (notice.kind) {
    PartyNoticeKind.paused =>
      notice.mine ? l.watchPartyNoticePausedByYou : l.watchPartyNoticePaused,
    PartyNoticeKind.resumed =>
      notice.mine ? l.watchPartyNoticeResumedByYou : l.watchPartyNoticeResumed,
    PartyNoticeKind.forcedResume => l.watchPartyNoticeForcedResume,
    PartyNoticeKind.seeked => notice.mine
        ? l.watchPartyNoticeSeekByYou(time)
        : l.watchPartyNoticeSeek(time),
    PartyNoticeKind.joined => l.watchPartyNoticeJoined(notice.name ?? ''),
    PartyNoticeKind.left => l.watchPartyNoticeLeft(notice.name ?? ''),
    PartyNoticeKind.nextEpisode =>
      l.watchPartyNoticeNextEpisode(notice.title ?? ''),
    PartyNoticeKind.nowWatching =>
      l.watchPartyNoticeNowWatching(notice.title ?? ''),
    PartyNoticeKind.resync => l.watchPartyNoticeResync,
    PartyNoticeKind.ended => l.watchPartyNoticeEnded,
  };
}

/// Avviso del watch party in alto al centro del player, visibile anche a
/// controlli nascosti (spec B §7.1).
class PartyNoticePill extends ConsumerWidget {
  const PartyNoticePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(partyNoticesProvider);
    if (notice == null) return const SizedBox.shrink();
    return Container(
      key: const Key('party-notice'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xE61B1B1B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WfColors.border),
      ),
      child: Text(partyNoticeText(AppLocalizations.of(context), notice),
          style: const TextStyle(color: WfColors.cream)),
    );
  }
}
