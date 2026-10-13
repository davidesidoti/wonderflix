import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/social/social_api.dart';
import '../auth/session_controller.dart';
import 'social_providers.dart';

/// "Mostra agli amici cosa guardo" dell'account aperto (spec O §7.3): sta
/// nel plugin, non nel dispositivo. Si rilegge a ogni cambio di profilo e
/// ogni volta che la sezione torna a vedersi (`autoDispose`).
class ShareActivityController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    return ref.watch(socialApiProvider).activitySettings();
  }

  /// Salva subito (spec O §7.3); non riuscito, torna com'era e risponde
  /// `false`.
  Future<bool> set(bool share) async {
    final previous = state.value;
    state = AsyncData(share);
    try {
      await ref.read(socialApiProvider).setActivitySettings(share);
      return true;
    } on SocialException {
      if (ref.mounted) state = AsyncData(previous ?? !share);
      return false;
    }
  }
}

final shareActivityProvider =
    AsyncNotifierProvider.autoDispose<ShareActivityController, bool>(
        ShareActivityController.new);
