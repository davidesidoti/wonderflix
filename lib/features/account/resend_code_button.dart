import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

/// "Rimanda il codice" (spec L §9.2, §9.3): attivo [delay] dopo l'ultimo
/// invio. Il conto parte quando il pulsante compare, cioè appena il codice
/// è partito, e riparte dopo un rinvio riuscito.
class ResendCodeButton extends StatefulWidget {
  const ResendCodeButton({super.key, required this.onResend});

  /// Come il limite del plugin: un codice al minuto.
  static const delay = Duration(seconds: 60);

  /// Rimanda il codice; `true` se è partito.
  final Future<bool> Function() onResend;

  @override
  State<ResendCodeButton> createState() => _ResendCodeButtonState();
}

class _ResendCodeButtonState extends State<ResendCodeButton> {
  /// Ogni quanto scende il conto.
  static const _tick = Duration(seconds: 1);

  Timer? _timer;
  int _secondsLeft = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _secondsLeft = ResendCodeButton.delay.inSeconds;
    _timer = Timer.periodic(_tick, (timer) {
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    final sent = await widget.onResend();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (sent) _restart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final waiting = _secondsLeft > 0;
    return TextButton(
      key: const Key('resend-code'),
      onPressed: waiting || _busy ? null : () => unawaited(_resend()),
      child: Text(
          waiting ? l.accountResendIn(_secondsLeft) : l.accountResendCode),
    );
  }
}
