import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/requests/requests_api.dart';
import '../../core/requests/requests_models.dart';
import '../social/social_providers.dart';

final requestsApiProvider =
    Provider<RequestsApi>((ref) => RequestsApi(ref.watch(jellyfinHttpProvider)));

/// Il plugin ha le richieste con Seerr (spec I §8.2). Senza, nell'app non
/// cambia nulla.
final requestsAvailableProvider = Provider<bool>((ref) =>
    ref.watch(socialAvailabilityProvider.select((f) => f.requests)));

/// Cosa può fare l'utente con Seerr. Si rilegge ogni volta che una pagina
/// lo usa di nuovo (`autoDispose`); senza la funzione, niente.
final requestsMeProvider = FutureProvider.autoDispose<RequestsMe>((ref) async {
  if (!ref.watch(requestsAvailableProvider)) return RequestsMe.none;
  return ref.watch(requestsApiProvider).me();
});
