import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/user_data.dart';

/// Toglie [item] da "Continua a guardare" (piano 2026-11-08, Task 2): punto
/// di ripresa a 0, come fa Jellyfin; lo stato "visto" non cambia. SnackBar
/// "Tolto" con Annulla, che rimanda il punto di prima, o con l'errore.
Future<void> removeFromResume(
  BuildContext context,
  WidgetRef ref,
  JellyfinItem item,
) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final overrides = ref.read(userDataOverridesProvider.notifier);
  final ticks = overrides.effective(item).playbackPositionTicks;
  if (!await _setPosition(overrides, item, 0, messenger, l)) return;
  messenger?.showSnackBar(
    SnackBar(
      content: Text(l.resumeHidden),
      action: SnackBarAction(
        label: l.actionUndo,
        onPressed: () =>
            unawaited(_setPosition(overrides, item, ticks, messenger, l)),
      ),
    ),
  );
}

/// `false` se non è riuscito: il punto torna com'era e la SnackBar lo dice.
Future<bool> _setPosition(
  UserDataOverrides overrides,
  JellyfinItem item,
  int ticks,
  ScaffoldMessengerState? messenger,
  AppLocalizations l,
) async {
  try {
    await overrides.setPlaybackPosition(item, ticks);
    return true;
  } on Object {
    messenger?.showSnackBar(SnackBar(content: Text(l.resumeChangeFailed)));
    return false;
  }
}
