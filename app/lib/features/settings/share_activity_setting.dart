import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../admin/admin_kit.dart';
import '../social/share_activity.dart';
import 'settings_kit.dart';

/// L'interruttore "Mostra agli amici cosa guardo" (spec O §7.3), una riga in
/// elenco. La larghezza la dà la pagina (640 px).
class ShareActivitySetting extends ConsumerWidget {
  const ShareActivitySetting({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref, bool share) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await ref.read(shareActivityProvider.notifier).set(share)) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l.settingsShareActivitySaveError)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final value = ref.watch(shareActivityProvider);
    final Widget row;
    if (value.hasError && !value.hasValue) {
      row = SettingsRow(
        label: l.settingsShareActivityLoadError,
        trailing: TextButton(
          key: const Key('share-activity-retry'),
          onPressed: () => ref.invalidate(shareActivityProvider),
          child: Text(l.retry),
        ),
      );
    } else {
      final share = value.value;
      row = SettingsSwitchRow(
        key: const Key('share-activity'),
        label: l.settingsShareActivity,
        hint: l.settingsShareActivityHint,
        // Mentre si legge (anche dopo un cambio di profilo) resta spento e
        // fermo: non mostra né cambia il valore dell'account precedente.
        value: share ?? false,
        onChanged: value.isLoading || share == null
            ? null
            : (next) => unawaited(_set(context, ref, next)),
      );
    }
    return AdminList(children: [row]);
  }
}
