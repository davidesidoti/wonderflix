import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'appearance_settings.dart';

/// Voce "Animazioni" (spec C §4.3).
class AppearanceSettingsSection extends ConsumerWidget {
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final setting = ref.watch(motionSettingProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.settingsAnimations),
          const SizedBox(height: 6),
          SegmentedButton<MotionSetting>(
            key: const Key('appearance-motion'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: MotionSetting.system,
                  label: Text(l.settingsAnimationsSystem)),
              ButtonSegment(
                  value: MotionSetting.full, label: Text(l.settingsAnimationsFull)),
              ButtonSegment(
                  value: MotionSetting.reduced,
                  label: Text(l.settingsAnimationsReduced)),
            ],
            selected: {setting},
            onSelectionChanged: (selection) => unawaited(
                ref.read(motionSettingProvider.notifier).set(selection.first)),
          ),
          const SizedBox(height: 8),
          Text(l.settingsAnimationsHint,
              style: const TextStyle(color: WfColors.creamMuted, fontSize: 12.5)),
        ],
      ),
    );
  }
}
