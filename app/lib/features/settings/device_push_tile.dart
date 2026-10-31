import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/push/web_push.dart';
import '../../l10n/gen/app_localizations.dart';
import 'device_push_controller.dart';

/// In cima a Impostazioni → Notifiche: le push su questo dispositivo. Solo
/// nel sito: l'app Windows non ha push del browser.
class DevicePushTile extends StatelessWidget {
  const DevicePushTile({super.key, this.inBrowser = kIsWeb});

  /// Nei test si prova anche il riquadro del sito.
  final bool inBrowser;

  @override
  Widget build(BuildContext context) =>
      inBrowser ? const _DevicePushTile() : const SizedBox.shrink();
}

class _DevicePushTile extends ConsumerWidget {
  const _DevicePushTile();

  Future<void> _run(BuildContext context, Future<bool> action) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await action) {
      messenger?.showSnackBar(
          SnackBar(content: Text(l.settingsShareActivitySaveError)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final availability = ref.watch(devicePushProvider).value;
    if (availability == null) return const SizedBox.shrink();
    final push = ref.read(devicePushProvider.notifier);
    Widget note(String text) =>
        Text(text, style: const TextStyle(color: WfColors.creamMuted));
    final child = switch (availability) {
      PushAvailability.unsupported => note(l.devicePushUnsupported),
      PushAvailability.needsHomeScreen => note(l.devicePushNeedsHomeScreen),
      PushAvailability.denied => note(l.devicePushDenied),
      PushAvailability.ready => Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            // Nessun await prima di activate: su iOS il permesso si chiede
            // solo dentro il tocco.
            onPressed: () => unawaited(_run(context, push.activate())),
            child: Text(l.devicePushActivate),
          ),
        ),
      PushAvailability.active => Row(
          children: [
            Expanded(child: Text(l.devicePushActive)),
            TextButton(
              onPressed: () => unawaited(_run(context, push.deactivate())),
              child: Text(l.devicePushDeactivate),
            ),
          ],
        ),
    };
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: child);
  }
}
