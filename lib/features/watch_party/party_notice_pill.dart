import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';
import 'party_notices.dart';
import 'party_queue_rules.dart';

String partyNoticeText(AppLocalizations l, PartyNotice notice) {
  final time = formatClock(notice.position ?? Duration.zero);
  final title = notice.title ?? '';
  // Chi ha agito, nelle azioni altrui annunciate dal canale (spec E §8).
  final by = notice.mine ? null : notice.name;
  return switch (notice.kind) {
    PartyNoticeKind.paused => notice.mine
        ? l.watchPartyNoticePausedByYou
        : by != null
            ? l.watchPartyNoticePausedBy(by)
            : l.watchPartyNoticePaused,
    PartyNoticeKind.resumed => notice.mine
        ? l.watchPartyNoticeResumedByYou
        : by != null
            ? l.watchPartyNoticeResumedBy(by)
            : l.watchPartyNoticeResumed,
    PartyNoticeKind.forcedResume => by != null
        ? l.watchPartyNoticeForcedResumeBy(by)
        : l.watchPartyNoticeForcedResume,
    PartyNoticeKind.seeked => notice.mine
        ? l.watchPartyNoticeSeekByYou(time)
        : by != null
            ? l.watchPartyNoticeSeekBy(by, time)
            : l.watchPartyNoticeSeek(time),
    PartyNoticeKind.joined => l.watchPartyNoticeJoined(notice.name ?? ''),
    PartyNoticeKind.left => l.watchPartyNoticeLeft(notice.name ?? ''),
    PartyNoticeKind.nextEpisode => by != null
        ? l.watchPartyNoticeNextEpisodeBy(by, title)
        : l.watchPartyNoticeNextEpisode(title),
    PartyNoticeKind.nextTitle => by != null
        ? l.watchPartyNoticeNextEpisodeBy(by, title)
        : l.watchPartyNoticeNextTitle(title),
    PartyNoticeKind.nowWatching => by != null
        ? l.watchPartyNoticeNowWatchingBy(by, title)
        : l.watchPartyNoticeNowWatching(title),
    PartyNoticeKind.resync => l.watchPartyNoticeResync,
    PartyNoticeKind.ended => l.watchPartyNoticeEnded,
    PartyNoticeKind.removed => l.watchPartyNoticeRemoved,
    PartyNoticeKind.privateCode => l.partyPrivateCreated(title),
    PartyNoticeKind.codeCopied => l.partyCodeCopied,
    PartyNoticeKind.inviteSent => l.partyInviteSent(notice.name ?? ''),
    PartyNoticeKind.inviteFailed => l.friendsActionFailed,
    PartyNoticeKind.inviteRateLimited => l.friendsTooMany,
    PartyNoticeKind.previousItem => by != null
        ? l.watchPartyNoticePreviousBy(by, title)
        : l.watchPartyNoticePrevious(title),
    PartyNoticeKind.shuffleOn => by != null
        ? l.watchPartyNoticeShuffleOnBy(by)
        : l.watchPartyNoticeShuffleOn,
    PartyNoticeKind.shuffleOff => by != null
        ? l.watchPartyNoticeShuffleOffBy(by)
        : l.watchPartyNoticeShuffleOff,
    PartyNoticeKind.queueFailed => l.partyQueueActionFailed,
    PartyNoticeKind.queued => notice.mine
        ? l.watchPartyNoticeQueuedByYou(_what(l, notice))
        : by != null
            ? l.watchPartyNoticeQueuedBy(by, _what(l, notice))
            : l.watchPartyNoticeQueued(_what(l, notice)),
    PartyNoticeKind.queuedNext => notice.mine
        ? l.watchPartyNoticeQueuedNextByYou(_what(l, notice))
        : by != null
            ? l.watchPartyNoticeQueuedNextBy(by, _what(l, notice))
            : l.watchPartyNoticeQueuedNext(_what(l, notice)),
    PartyNoticeKind.queueRejected => l.partyQueueRejected,
    PartyNoticeKind.queuePartial => notice.series != null
        ? l.partyQueuePartialEpisodes(notice.count ?? 0, notice.total ?? 0)
        : l.partyQueuePartialTitles(notice.count ?? 0, notice.total ?? 0),
    PartyNoticeKind.queueFull => l.partyQueueFull(partyQueueLimit),
  };
}

/// Cosa si è aggiunto (spec H §10): il titolo, "8 episodi di Dark" o "3
/// titoli".
String _what(AppLocalizations l, PartyNotice notice) {
  final title = notice.title;
  if (title != null) return title;
  final count = notice.count ?? 0;
  final series = notice.series;
  return series != null
      ? l.partyQueueWhatEpisodes(count, series)
      : l.catalogCount(count);
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
      PartyNoticeKind.nextEpisode ||
      PartyNoticeKind.nextTitle =>
        LucideIcons.skipForward,
      PartyNoticeKind.nowWatching => LucideIcons.clapperboard,
      PartyNoticeKind.resync => LucideIcons.refreshCw,
      PartyNoticeKind.ended => LucideIcons.circleStop,
      PartyNoticeKind.removed => LucideIcons.logOut,
      PartyNoticeKind.privateCode => LucideIcons.lock,
      PartyNoticeKind.codeCopied => LucideIcons.copy,
      PartyNoticeKind.inviteSent => LucideIcons.send,
      PartyNoticeKind.previousItem => LucideIcons.skipBack,
      PartyNoticeKind.shuffleOn ||
      PartyNoticeKind.shuffleOff =>
        LucideIcons.shuffle,
      PartyNoticeKind.queued => LucideIcons.listPlus,
      PartyNoticeKind.queuedNext => LucideIcons.listStart,
      PartyNoticeKind.inviteFailed ||
      PartyNoticeKind.inviteRateLimited ||
      PartyNoticeKind.queueFailed ||
      PartyNoticeKind.queueRejected ||
      PartyNoticeKind.queuePartial ||
      PartyNoticeKind.queueFull =>
        LucideIcons.circleAlert,
    };
