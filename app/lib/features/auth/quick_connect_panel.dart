import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/error_text.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
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
    _subscription = ref.read(quickConnectRunnerProvider).run().listen(
      (state) {
        if (!mounted) return;
        setState(() => _state = state);
        if (state is QcApproved) {
          ref
              .read(sessionControllerProvider.notifier)
              .quickConnectApproved(state.user);
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _state = QcError(e));
      },
    );
  }

  void _restart() {
    setState(() => _state = const QcLoading());
    _listen();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const muted =
        TextStyle(color: WfColors.creamMuted, fontSize: 12.5, height: 1.45);
    const spinner = Center(
      child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5)),
    );

    return switch (_state) {
      QcLoading() || QcApproved() => spinner,
      QcDisabled() => Text(l.quickConnectDisabled, style: muted),
      QcWaiting(:final code) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.quickConnectYourCode),
            const SizedBox(height: 6),
            // Su un telefono stretto, o col testo ingrandito, il codice si
            // rimpicciolisce invece di andare a capo.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatQuickConnectCode(code),
                maxLines: 1,
                textAlign: TextAlign.center,
                style: WfText.display(68, color: WfColors.gold).copyWith(
                  letterSpacing: 6,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
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
            const Divider(height: 1, color: WfColors.border),
            const SizedBox(height: 14),
            _Step(
                1,
                l.quickConnectStepOpen('${l.menuSettings} › '
                    '${l.settingsAccount} › ${l.settingsQuickConnect}')),
            const SizedBox(height: 10),
            _Step(2, l.quickConnectStepCode(l.authorizeDeviceSubmit)),
            _AdminHelp(muted: muted),
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

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: WfColors.gold),
            ),
            child: Text('$number',
                style: const TextStyle(
                    color: WfColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text,
                  style: const TextStyle(
                      color: WfColors.cream, fontSize: 14, height: 1.4)),
            ),
          ),
        ],
      );
}

/// Chi non ha un altro dispositivo: fuori dalla TV un link al contatto di
/// supporto, in TV solo il testo (nessun browser da aprire).
class _AdminHelp extends ConsumerWidget {
  const _AdminHelp({required this.muted});

  final TextStyle muted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final supportUrl = ref.watch(appConfigProvider).supportUrl;
    if (supportUrl == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: FormFactor.of(context).tv
          ? Text(l.quickConnectAskAdmin,
              style: muted, textAlign: TextAlign.center)
          : Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l.quickConnectNoDevice, style: muted),
                TextButton(
                  onPressed: () => unawaited(launchUrl(supportUrl)),
                  child: Text(l.loginContactAdmin),
                ),
              ],
            ),
    );
  }
}
