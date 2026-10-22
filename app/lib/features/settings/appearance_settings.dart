import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../core/system/windows_animation_pref.dart';

/// Voce "Animazioni" delle impostazioni (spec C §4.3).
enum MotionSetting { system, full, reduced }

/// Livello effettivo (spec C §4.5).
MotionLevel resolveMotionLevel(MotionSetting setting,
        {required bool systemAnimations}) =>
    switch (setting) {
      MotionSetting.full => MotionLevel.full,
      MotionSetting.reduced => MotionLevel.reduced,
      MotionSetting.system =>
        systemAnimations ? MotionLevel.full : MotionLevel.reduced,
    };

/// Impostazioni "Aspetto" (spec C §4.3): per ora la sola voce
/// "Animazioni".
class AppearanceSettingsController extends Notifier<MotionSetting> {
  static const _key = 'appearance.motion';

  @override
  MotionSetting build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_key);
    return MotionSetting.values.asNameMap()[saved] ?? MotionSetting.system;
  }

  Future<void> set(MotionSetting value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).setString(_key, value.name);
  }
}

final motionSettingProvider =
    NotifierProvider<AppearanceSettingsController, MotionSetting>(
        AppearanceSettingsController.new);

/// Sostituito nei test.
final animationPreferenceProvider =
    Provider<AnimationPreference>((ref) => WindowsAnimationPreference());

/// "Effetti di animazione" di Windows; [refresh] al ritorno del focus.
class SystemAnimationsController extends Notifier<bool> {
  @override
  bool build() => ref.watch(animationPreferenceProvider).animationsEnabled();

  void refresh() =>
      state = ref.read(animationPreferenceProvider).animationsEnabled();
}

final systemAnimationsProvider =
    NotifierProvider<SystemAnimationsController, bool>(
        SystemAnimationsController.new);

final motionLevelProvider = Provider<MotionLevel>((ref) => resolveMotionLevel(
      ref.watch(motionSettingProvider),
      systemAnimations: ref.watch(systemAnimationsProvider),
    ));
