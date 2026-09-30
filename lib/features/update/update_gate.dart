import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../app/motion.dart';
import '../player/player_active.dart';
import 'mandatory_update_screen.dart';
import 'update_banner.dart';
import 'update_controller.dart';

/// La schermata bloccante è visibile: l'app sotto non deve reagire (né ai
/// clic né a Esc / Alt+←).
final updateBlockedProvider = Provider<bool>((ref) {
  final update = ref.watch(updateControllerProvider);
  return update.release != null &&
      update.mandatory &&
      !ref.watch(playerActiveProvider);
});

/// Sopra tutte le schermate (nel `builder` di `MaterialApp.router`): barra
/// "Aggiornamento pronto" o schermata bloccante, mai mentre il player è
/// aperto. L'app resta montata sotto, così lo stato della navigazione non si
/// perde.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  /// Versione rimandata con "Più tardi" (fino al prossimo avvio).
  Version? _postponed;

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(updateControllerProvider);
    final playing = ref.watch(playerActiveProvider);
    final blocked = ref.watch(updateBlockedProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final release = update.release;

    final showBanner = release != null &&
        update.ready &&
        !update.mandatory &&
        !playing &&
        _postponed != release.version;
    final duration = WfMotion.of(context).duration(WfMotion.medium);
    final banner = showBanner
        ? UpdateBanner(
            key: ValueKey(release.version.toString()),
            release: release,
            onRestart: () => unawaited(controller.install()),
            onLater: () => setState(() => _postponed = release.version),
          )
        : const SizedBox.shrink();
    final screen = blocked
        ? MandatoryUpdateScreen(
            key: const ValueKey('mandatory-update'),
            update: update,
            onInstall: () => unawaited(controller.install()),
            onRetry: controller.retry,
          )
        : const SizedBox.shrink(key: ValueKey('no-update'));

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: blocked,
          child: ExcludeFocus(excluding: blocked, child: widget.child),
        ),
        // La barra sale dal basso (è in basso) e scende sparendo.
        Positioned(
          left: 24,
          right: 24,
          bottom: 24,
          child: Center(
            child: AnimatedSwitcher(
              duration: duration,
              transitionBuilder: (child, animation) => IgnorePointer(
                // La barra che se ne va non accetta più "Riavvia ora".
                ignoring: child.key != banner.key,
                child: FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position:
                        Tween(begin: const Offset(0, 0.5), end: Offset.zero)
                            .animate(CurvedAnimation(
                                parent: animation,
                                curve: WfMotion.emphasized)),
                    child: child,
                  ),
                ),
              ),
              child: banner,
            ),
          ),
        ),
        // La schermata bloccante compare e sparisce in dissolvenza.
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: duration,
            // Mentre sfuma via non copre più l'app.
            transitionBuilder: (child, animation) => IgnorePointer(
              ignoring: child.key != screen.key,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: screen,
          ),
        ),
      ],
    );
  }
}
