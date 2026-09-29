import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'quick_connect_flow.dart';

/// `true` se il server ha Quick Connect attivo. In caso di errore: `false`
/// (la scheda semplicemente non compare).
final quickConnectEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(authApiProvider).quickConnectEnabled();
  } on Object {
    return false;
  }
});

final quickConnectRunnerProvider = Provider<QuickConnectRunner>(
  (ref) => QuickConnectFlow(
    api: ref.watch(authApiProvider),
    auth: ref.watch(authServiceProvider),
  ),
);
