import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../social/share_activity.dart';

/// Larghezza massima della riga, come le altre impostazioni.
const _shareActivityMaxWidth = 640.0;

/// L'interruttore "Mostra agli amici cosa guardo" (spec O §7.3).
class ShareActivitySetting extends ConsumerWidget {
  const ShareActivitySetting({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref, bool share) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await ref.read(shareActivityProvider.notifier).set(share)) {
      messenger?.showSnackBar(
          SnackBar(content: Text(l.settingsShareActivitySaveError)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final value = ref.watch(shareActivityProvider);
    final Widget child;
    if (value.hasError && !value.hasValue) {
      child = Row(
        children: [
          Expanded(
            child: Text(l.settingsShareActivityLoadError,
                style: const TextStyle(color: WfColors.creamMuted)),
          ),
          TextButton(
            key: const Key('share-activity-retry'),
            onPressed: () => ref.invalidate(shareActivityProvider),
            child: Text(l.retry),
          ),
        ],
      );
    } else {
      final share = value.value;
      child = SwitchListTile(
        key: const Key('share-activity'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.settingsShareActivity),
        subtitle: Text(l.settingsShareActivityHint),
        // Mentre si legge (anche dopo un cambio di profilo) resta spento e
        // fermo: non mostra né cambia il valore dell'account precedente.
        value: share ?? false,
        onChanged: value.isLoading || share == null
            ? null
            : (next) => unawaited(_set(context, ref, next)),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _shareActivityMaxWidth),
        child: child,
      ),
    );
  }
}
