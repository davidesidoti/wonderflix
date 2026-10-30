import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/space/space_api.dart';
import '../../core/space/space_models.dart';
import 'space_controller.dart';
import 'space_providers.dart';

/// Un'operazione sullo spazio, riletta ogni secondo finché è in coda o in
/// corso (decisione 6 del piano 30b). Si ferma a `notFound` e quando il
/// riquadro si chiude; chiuderlo non ferma l'operazione.
class SpaceOperationController extends AsyncNotifier<SpaceOperation> {
  SpaceOperationController(this.id);

  final String id;

  Timer? _timer;

  @override
  Future<SpaceOperation> build() async {
    ref.onDispose(() => _timer?.cancel());
    final op = await ref.watch(spaceApiProvider).operation(id);
    if (op.running && ref.mounted) _schedule();
    return op;
  }

  void _schedule() => _timer = Timer(const Duration(seconds: 1), _poll);

  Future<void> _poll() async {
    try {
      final op = await ref.read(spaceApiProvider).operation(id);
      if (!ref.mounted) return;
      state = AsyncData(op);
      if (op.running) {
        _schedule();
      } else {
        await ref.read(spaceControllerProvider.notifier).reload();
      }
    } on SpaceException catch (e, stack) {
      if (!ref.mounted) return;
      // Una rete che cade riprova; un'operazione sparita no.
      if (e.failure == SpaceFailure.notFound) {
        state = AsyncError(e, stack);
      } else {
        _schedule();
      }
    }
  }
}

final spaceOperationProvider = AsyncNotifierProvider.autoDispose
    .family<SpaceOperationController, SpaceOperation, String>(
      SpaceOperationController.new,
    );
