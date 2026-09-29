import 'package:flutter/material.dart';

import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Unico punto d'ingresso per avviare la riproduzione.
/// Il Piano 3 lo collega al player; per ora avvisa l'utente.
void playItem(BuildContext context, JellyfinItem item, {bool fromStart = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).playbackComingSoon)));
}
