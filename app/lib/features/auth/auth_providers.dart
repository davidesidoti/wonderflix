import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'quick_connect_flow.dart';

/// `true` se il server ha Quick Connect attivo. In caso di errore: `true`,
/// così la scheda c'è e mostra l'errore con "Riprova" (sulla TV è l'unico
/// modo comodo per entrare, e senza la scheda il guasto restava muto).
final quickConnectEnabledProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await ref.watch(authApiProvider).quickConnectEnabled();
  } on Object {
    return true;
  }
});

final quickConnectRunnerProvider = Provider<QuickConnectRunner>(
  (ref) => QuickConnectFlow(
    api: ref.watch(authApiProvider),
    auth: ref.watch(authServiceProvider),
  ),
);
