import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../admin/admin_kit.dart';
import 'appearance_settings.dart';
import 'locale_controller.dart';
import 'settings_kit.dart';

/// Sezione App: lingua dell'app e "Animazioni" (spec C §4.3).
class AppearanceSettingsSection extends ConsumerWidget {
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final setting = ref.watch(motionSettingProvider);
    final locale = ref.watch(localeProvider);
    return AdminList(
      children: [
        SettingsRow(
          label: l.settingsLanguageApp,
          wideTrailing: true,
          trailing: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: 'system', label: Text(l.settingsLanguageSystem)),
              const ButtonSegment(value: 'it', label: Text('Italiano')),
              const ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {locale?.languageCode ?? 'system'},
            onSelectionChanged: (selection) {
              final code = selection.first;
              unawaited(ref
                  .read(localeProvider.notifier)
                  .set(code == 'system' ? null : Locale(code)));
            },
          ),
        ),
        // La TV non ha animazioni da scegliere.
        if (!FormFactor.of(context).tv)
          SettingsRow(
            label: l.settingsAnimations,
            hint:
                kIsWeb ? l.settingsAnimationsHintWeb : l.settingsAnimationsHint,
            wideTrailing: true,
            trailing: SegmentedButton<MotionSetting>(
              key: const Key('appearance-motion'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: MotionSetting.system,
                    label: Text(kIsWeb
                        ? l.settingsAnimationsSystemWeb
                        : l.settingsAnimationsSystem)),
                ButtonSegment(
                    value: MotionSetting.full,
                    label: Text(l.settingsAnimationsFull)),
                ButtonSegment(
                    value: MotionSetting.reduced,
                    label: Text(l.settingsAnimationsReduced)),
              ],
              selected: {setting},
              onSelectionChanged: (selection) => unawaited(
                  ref.read(motionSettingProvider.notifier).set(selection.first)),
            ),
          ),
      ],
    );
  }
}
