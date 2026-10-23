import 'dart:ui' show PlatformDispatcher;

import 'animation_preference.dart';

AnimationPreference createAnimationPreference() =>
    _BrowserAnimationPreference();

/// Nel browser vale `prefers-reduced-motion`, che Flutter passa come
/// `disableAnimations`.
class _BrowserAnimationPreference implements AnimationPreference {
  @override
  bool animationsEnabled() =>
      !PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;
}
