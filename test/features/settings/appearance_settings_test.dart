import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/system/windows_animation_pref.dart';
import 'package:wonderflix/features/settings/appearance_settings.dart';

class FakeAnimationPreference implements AnimationPreference {
  FakeAnimationPreference(this.enabled);

  bool enabled;
  int reads = 0;

  @override
  bool animationsEnabled() {
    reads++;
    return enabled;
  }
}

void main() {
  test('resolveMotionLevel: tabella dello spec §4.5', () {
    expect(resolveMotionLevel(MotionSetting.system, systemAnimations: true),
        MotionLevel.full);
    expect(resolveMotionLevel(MotionSetting.system, systemAnimations: false),
        MotionLevel.reduced);
    expect(resolveMotionLevel(MotionSetting.full, systemAnimations: false),
        MotionLevel.full);
    expect(resolveMotionLevel(MotionSetting.reduced, systemAnimations: true),
        MotionLevel.reduced);
  });

  Future<(ProviderContainer, FakeAnimationPreference, SharedPreferences)>
      setUpContainer(
          {Map<String, Object> values = const {}, bool system = true}) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final pref = FakeAnimationPreference(system);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      animationPreferenceProvider.overrideWithValue(pref),
    ]);
    addTearDown(container.dispose);
    return (container, pref, prefs);
  }

  test('predefinito: Come Windows', () async {
    final (container, _, _) = await setUpContainer(system: false);
    expect(container.read(motionSettingProvider), MotionSetting.system);
    expect(container.read(motionLevelProvider), MotionLevel.reduced);
  });

  test('l\'impostazione si salva e si rilegge', () async {
    final (container, _, prefs) = await setUpContainer();
    await container
        .read(motionSettingProvider.notifier)
        .set(MotionSetting.reduced);
    expect(prefs.getString('appearance.motion'), 'reduced');
    expect(container.read(motionLevelProvider), MotionLevel.reduced);

    final (other, _, _) = await setUpContainer(
        values: {'appearance.motion': 'full'}, system: false);
    expect(other.read(motionSettingProvider), MotionSetting.full);
    expect(other.read(motionLevelProvider), MotionLevel.full);
  });

  test('valore salvato sconosciuto: Come Windows', () async {
    final (container, _, _) =
        await setUpContainer(values: {'appearance.motion': 'boh'});
    expect(container.read(motionSettingProvider), MotionSetting.system);
  });

  test('refresh rilegge la preferenza di Windows', () async {
    final (container, pref, _) = await setUpContainer();
    expect(container.read(motionLevelProvider), MotionLevel.full);
    pref.enabled = false;
    container.read(systemAnimationsProvider.notifier).refresh();
    expect(container.read(motionLevelProvider), MotionLevel.reduced);
    expect(pref.reads, 2);
  });
}
