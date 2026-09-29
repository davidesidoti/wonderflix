import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'auth_providers.dart';
import 'quick_connect_flow.dart';
import 'session_controller.dart';

String formatQuickConnectCode(String code) =>
    code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

class QuickConnectPanel extends ConsumerStatefulWidget {
  const QuickConnectPanel({super.key});

  @override
  ConsumerState<QuickConnectPanel> createState() => _QuickConnectPanelState();
}

class _QuickConnectPanelState extends ConsumerState<QuickConnectPanel> {
  StreamSubscription<QcState>? _subscription;
  QcState _state = const QcLoading();

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _listen() {
    unawaited(_subscription?.cancel());
    _subscription =
        ref.read(quickConnectRunnerProvider).run().listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
      if (state is QcApproved) {
        ref.read(sessionControllerProvider.notifier).quickConnectApproved(state.user);
      }
    });
  }

  void _restart() {
    setState(() => _state = const QcLoading());
    _listen();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 12.5, height: 1.45);
    const spinner = Center(
      child: SizedBox(
          width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
    );

    return switch (_state) {
      QcLoading() || QcApproved() => spinner,
      QcDisabled() => Text(l.quickConnectDisabled, style: muted),
      QcWaiting(:final code) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.quickConnectYourCode),
            const SizedBox(height: 6),
            Text(
              formatQuickConnectCode(code),
              textAlign: TextAlign.center,
              style: WfText.display(52, color: WfColors.gold)
                  .copyWith(letterSpacing: 10),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Flexible(child: Text(l.quickConnectWaiting)),
              ],
            ),
            const SizedBox(height: 14),
            Text(l.quickConnectHelp, style: muted),
          ],
        ),
      QcError(:final error) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(describeError(l, error), style: muted),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _restart, child: Text(l.retry)),
          ],
        ),
    };
  }
}
