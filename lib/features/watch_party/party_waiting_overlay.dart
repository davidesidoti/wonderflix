import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';

/// Il gruppo aspetta qualcuno (buffering, ingresso di un membro). Compare
/// dopo [delay], per non lampeggiare nelle attese brevi (spec B §7.1).
class PartyWaitingOverlay extends StatefulWidget {
  const PartyWaitingOverlay({
    super.key,
    required this.waiting,
    required this.onResume,
  });

  static const delay = Duration(seconds: 1);

  final bool waiting;

  /// "Riprendi senza aspettare".
  final VoidCallback onResume;

  @override
  State<PartyWaitingOverlay> createState() => _PartyWaitingOverlayState();
}

class _PartyWaitingOverlayState extends State<PartyWaitingOverlay> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PartyWaitingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waiting != widget.waiting) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    _visible = false;
    if (!widget.waiting) return;
    _timer = Timer(PartyWaitingOverlay.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return ColoredBox(
      color: const Color(0x99000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.hourglass, size: 40, color: WfColors.gold),
            const SizedBox(height: 16),
            Text(l.watchPartyWaiting, style: WfText.display(28)),
            const SizedBox(height: 20),
            WfButton.secondary(
              label: l.watchPartyResumeNow,
              icon: LucideIcons.play,
              onPressed: widget.onResume,
            ),
          ],
        ),
      ),
    );
  }
}
