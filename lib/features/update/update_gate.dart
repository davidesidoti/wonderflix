import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pub_semver/pub_semver.dart';

import '../player/player_active.dart';
import 'mandatory_update_screen.dart';
import 'update_banner.dart';
import 'update_controller.dart';

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
    final controller = ref.read(updateControllerProvider.notifier);
    final release = update.release;

    final blocked = release != null && update.mandatory && !playing;
    final showBanner = release != null &&
        update.ready &&
        !update.mandatory &&
        !playing &&
        _postponed != release.version;

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: blocked,
          child: ExcludeFocus(excluding: blocked, child: widget.child),
        ),
        if (showBanner)
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: Center(
              child: UpdateBanner(
                release: release,
                onRestart: () => unawaited(controller.install()),
                onLater: () => setState(() => _postponed = release.version),
              ),
            ),
          ),
        if (blocked)
          Positioned.fill(
            child: MandatoryUpdateScreen(
              update: update,
              onInstall: () => unawaited(controller.install()),
              onRetry: controller.retry,
            ),
          ),
      ],
    );
  }
}
