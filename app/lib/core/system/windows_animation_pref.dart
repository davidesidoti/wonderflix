import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';

/// Preferenza di sistema per le animazioni.
abstract interface class AnimationPreference {
  /// `true` se il sistema ha le animazioni attive.
  bool animationsEnabled();
}

/// `SPI_GETCLIENTAREAANIMATION`: voce "Effetti di animazione" di Windows.
const _spiGetClientAreaAnimation = 0x1042;

/// Legge "Effetti di animazione" con `SystemParametersInfoW`. Flutter su
/// Windows non la passa a `MediaQuery.disableAnimations` (spec C §4.4).
class WindowsAnimationPreference implements AnimationPreference {
  static final _log = Logger('motion');

  @override
  bool animationsEnabled() {
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final systemParametersInfo = user32.lookupFunction<
          Int32 Function(Uint32, Uint32, Pointer<Void>, Uint32),
          int Function(int, int, Pointer<Void>, int)>('SystemParametersInfoW');
      final value = calloc<Int32>();
      try {
        final ok = systemParametersInfo(
            _spiGetClientAreaAnimation, 0, value.cast(), 0);
        if (ok == 0) {
          _log.warning('SystemParametersInfoW non riuscita: animazioni complete');
          return true;
        }
        return value.value != 0;
      } finally {
        calloc.free(value);
      }
    } on Object catch (e) {
      _log.warning('preferenza delle animazioni non leggibile: $e');
      return true;
    }
  }
}
