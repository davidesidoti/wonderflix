import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
    PartyNoticeKind.removed => l.watchPartyNoticeRemoved,
  };
}

/// Icona oro dell'avviso nella pillola del player (spec D §15.1).
IconData partyNoticeIcon(PartyNoticeKind kind) => switch (kind) {
      PartyNoticeKind.paused => LucideIcons.pause,
      PartyNoticeKind.resumed ||
      PartyNoticeKind.forcedResume =>
        LucideIcons.play,
      PartyNoticeKind.seeked => LucideIcons.fastForward,
      PartyNoticeKind.joined => LucideIcons.userPlus,
      PartyNoticeKind.left => LucideIcons.userMinus,
      PartyNoticeKind.nextEpisode => LucideIcons.skipForward,
      PartyNoticeKind.nowWatching => LucideIcons.clapperboard,
      PartyNoticeKind.resync => LucideIcons.refreshCw,
      PartyNoticeKind.ended => LucideIcons.circleStop,
      PartyNoticeKind.removed => LucideIcons.logOut,
    };
