import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/json_fields.dart';
import '../../core/social/social_api.dart';
import '../auth/session_controller.dart';
import '../social/social_providers.dart';

final _log = Logger('social');

/// I titoli tolti da "Consigliati per te" con "Non mi interessa" (spec N
/// §7.4): la card sparisce subito, prima della risposta del plugin, e torna
/// se la chiamata non riesce (piano 20b, decisione 2). Chiavi
/// `jellyfinIdKey`. Si svuota al cambio di utente.
class RecommendationDismissals extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    return const {};
  }

  /// Toglie [itemId]; `false` se il plugin non ha risposto (la card torna).
  Future<bool> dismiss(String itemId) async {
    final key = jellyfinIdKey(itemId);
    state = {...state, key};
    try {
      await ref.read(socialApiProvider).dismissRecommendation(itemId);
      return true;
    } on Object catch (error) {
      _log.info('consiglio non tolto: '
          '${error is SocialException ? error.failure.name : error.runtimeType}');
      if (ref.mounted) state = {...state}..remove(key);
      return false;
    }
  }
}

final recommendationDismissalsProvider =
    NotifierProvider<RecommendationDismissals, Set<String>>(
        RecommendationDismissals.new);
