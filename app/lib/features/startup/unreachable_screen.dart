import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../auth/session_controller.dart';

class UnreachableScreen extends ConsumerStatefulWidget {
  const UnreachableScreen({super.key});

  static const retryInterval = Duration(seconds: 15);

  @override
  ConsumerState<UnreachableScreen> createState() => _UnreachableScreenState();
}

class _UnreachableScreenState extends ConsumerState<UnreachableScreen> {
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
        UnreachableScreen.retryInterval, (_) => unawaited(_retry()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Riapre il profilo scelto che non si è aperto, se c'è (con più profili
  /// `restore` porterebbe solo a "Chi guarda?" senza chiedere niente al
  /// server); altrimenti riparte da `restore`.
  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionControllerProvider.notifier);
      final current = ref.read(sessionControllerProvider);
      final retryUserId =
          current is SessionUnreachable ? current.retryUserId : null;
      await (retryUserId != null
          ? session.openProfile(retryUserId)
          : session.restore());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider);
    final retryUserId =
        session is SessionUnreachable ? session.retryUserId : null;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.wifiOff, size: 48, color: WfColors.gold),
            const SizedBox(height: 20),
            Text(l.unreachableTitle, style: WfText.display(36)),
            const SizedBox(height: 8),
            Text(l.unreachableBody,
                style: const TextStyle(color: WfColors.creamMuted)),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              child: FilledButton(
                onPressed: _busy ? null : _retry,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: WfColors.bg),
                      )
                    : Text(l.retry),
              ),
            ),
            // Il profilo scelto non si apre: si può tornare a "Chi guarda?",
            // perché l'errore può essere di quel profilo e "Riprova" non
            // riuscirebbe mai.
            if (retryUserId != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 200,
                child: WfButton.secondary(
                  label: l.profilesSwitch,
                  icon: LucideIcons.users,
                  onPressed: _busy
                      ? null
                      : ref
                          .read(sessionControllerProvider.notifier)
                          .backToProfiles,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
