import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/syncplay/party_mode.dart';
import '../../l10n/gen/app_localizations.dart';

IconData partyModeIcon(PartyMode mode) => switch (mode) {
      PartyMode.public => LucideIcons.globe,
      PartyMode.friends => LucideIcons.users,
      PartyMode.private => LucideIcons.lock,
    };

String partyModeLabel(AppLocalizations l, PartyMode mode) => switch (mode) {
      PartyMode.public => l.partyModePublic,
      PartyMode.friends => l.partyModeFriends,
      PartyMode.private => l.partyModePrivate,
    };

String partyModeHint(AppLocalizations l, PartyMode mode) => switch (mode) {
      PartyMode.public => l.partyModePublicHint,
      PartyMode.friends => l.partyModeFriendsHint,
      PartyMode.private => l.partyModePrivateHint,
    };
