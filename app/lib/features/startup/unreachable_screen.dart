import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_buttons.dart';
import '../admin/admin_kit.dart';
import '../auth/auth_service.dart';
import '../auth/session_controller.dart';

class UnreachableScreen extends ConsumerStatefulWidget {
  const UnreachableScreen({super.key});

  /// Secondi tra un tentativo automatico e il successivo.
  static const retrySeconds = 15;

  @override
  ConsumerState<UnreachableScreen> createState() => _UnreachableScreenState();
}

class _UnreachableScreenState extends ConsumerState<UnreachableScreen> {
  Timer? _timer;
  bool _busy = false;

  /// Secondi al prossimo tentativo automatico.
  int _left = UnreachableScreen.retrySeconds;

  /// Quando la schermata si è aperta: l'attesa non si azzera a ogni
  /// tentativo, né quando il motivo cambia. Con l'orologio e non coi battiti,
  /// che in una scheda in background rallentano.
  final DateTime _since = clock.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    setState(() {
      if (!_busy && _left > 0) _left--;
    });
    if (!_busy && _left == 0) unawaited(_retry());
  }

  /// Riapre il profilo scelto che non si è aperto, se c'è (con più profili
  /// `restore` porterebbe solo a "Chi guarda?" senza chiedere niente al
  /// server); altrimenti riparte da `restore`. Alla fine il conto riparte.
  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionControllerProvider.notifier);
      final current = ref.read(sessionControllerProvider);
      final retryUserId = current is SessionUnreachable
          ? current.retryUserId
          : null;
      await (retryUserId != null
          ? session.openProfile(retryUserId)
          : session.restore());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _left = UnreachableScreen.retrySeconds;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final form = FormFactor.of(context);
    final phone = form.compact && !form.tv;
    final reducedMotion = WfMotion.of(context).isReduced;
    final session = ref.watch(sessionControllerProvider);
    final unreachable = session is SessionUnreachable ? session : null;
    final retryUserId = unreachable?.retryUserId;
    final reason = unreachable?.reason ?? UnreachableReason.notResponding;
    final offline = reason == UnreachableReason.offline;
    final (title, body) = switch (reason) {
      UnreachableReason.offline => (
        l.unreachableOfflineTitle,
        l.unreachableOfflineBody,
      ),
      UnreachableReason.starting => (
        l.unreachableStartingTitle,
        l.unreachableStartingBody,
      ),
      UnreachableReason.notResponding => (
        l.unreachableDownTitle,
        l.unreachableDownBody,
      ),
    };
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    const tabular = [FontFeature.tabularFigures()];
    final waitedMinutes = clock.now().difference(_since).inMinutes;

    final buttons = [
      WfButton.primary(
        label: l.unreachableRetryNow,
        icon: LucideIcons.refreshCw,
        autofocus: form.tv,
        // Sempre acceso: un pulsante spento perde il focus della TV a ogni
        // tentativo. Durante il tentativo `_retry` non fa niente.
        onPressed: _retry,
      ),
      // Il profilo scelto non si apre: si può tornare a "Chi guarda?",
      // perché l'errore può essere di quel profilo e "Riprova" non
      // riuscirebbe mai. Durante un tentativo non fa niente: il profilo
      // potrebbe aprirsi subito dopo.
      if (retryUserId != null)
        WfButton.secondary(
          label: l.profilesSwitch,
          icon: LucideIcons.users,
          onPressed: () {
            if (!_busy) {
              ref.read(sessionControllerProvider.notifier).backToProfiles();
            }
          },
        ),
    ];

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: _LampPill(
                      lampKey: const Key('lamp-connection'),
                      state: offline ? LampState.broken : LampState.ok,
                      label: l.unreachableLampConnection,
                    ),
                  ),
                  Container(
                    width: phone ? 28 : 64,
                    height: 1.5,
                    color: WfColors.border,
                  ),
                  Flexible(
                    child: _LampPill(
                      lampKey: const Key('lamp-server'),
                      state: offline ? LampState.off : LampState.attention,
                      label: l.unreachableLampServer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                title,
                textAlign: TextAlign.center,
                style: WfText.display(phone ? 48 : 68),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: WfColors.creamMuted,
                        fontSize: 15,
                      ),
                    ),
                    if (offline) ...[
                      const SizedBox(height: 8),
                      Text(
                        l.unreachableOfflineHint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: WfColors.creamMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: phone ? double.infinity : 360,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            _busy
                                ? l.unreachableRetrying
                                : l.unreachableRetryIn(_left),
                            style: muted.copyWith(fontFeatures: tabular),
                          ),
                        ),
                        if (waitedMinutes >= 2) ...[
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              l.unreachableWaiting(waitedMinutes),
                              textAlign: TextAlign.end,
                              style: muted.copyWith(fontFeatures: tabular),
                            ),
                          ),
                        ],
                      ],
                    ),
                    // L'unico movimento della pagina: fermo con il movimento
                    // ridotto.
                    if (!reducedMotion) ...[
                      const SizedBox(height: 8),
                      TweenAnimationBuilder<double>(
                        key: const Key('retry-line'),
                        tween: Tween(
                          begin: 0,
                          end: 1 - _left / UnreachableScreen.retrySeconds,
                        ),
                        // Dopo un tentativo torna vuota di colpo, senza
                        // scorrere all'indietro.
                        duration: _left == UnreachableScreen.retrySeconds
                            ? Duration.zero
                            : const Duration(seconds: 1),
                        builder: (context, value, _) => Container(
                          height: 3,
                          color: WfColors.border,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: value,
                            heightFactor: 1,
                            child: const ColoredBox(color: WfColors.gold),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (phone)
                for (final (i, button) in buttons.indexed) ...[
                  if (i > 0) const SizedBox(height: 12),
                  SizedBox(width: double.infinity, height: 46, child: button),
                ]
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, button) in buttons.indexed) ...[
                      if (i > 0) const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 170),
                        child: button,
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una pastiglia della catena: la spia e il nome di quello che controlla.
class _LampPill extends StatelessWidget {
  const _LampPill({
    required this.lampKey,
    required this.state,
    required this.label,
  });

  final Key lampKey;
  final LampState state;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 13),
    decoration: BoxDecoration(
      color: WfColors.surface,
      border: Border.all(color: WfColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WfLamp(key: lampKey, state: state, label: label),
        const SizedBox(width: 8),
        Flexible(
          child: ExcludeSemantics(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: WfColors.creamMuted, fontSize: 13),
            ),
          ),
        ),
      ],
    ),
  );
}
