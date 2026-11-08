import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/error_text.dart';
import '../../app/providers.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/jellyfin_http.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import '../auth/password_login_form.dart';
import 'account_texts.dart';

/// Conferma il codice Quick Connect di un altro dispositivo (la TV) per
/// l'utente aperto (piano TV 3). `true` se è autorizzato.
Future<bool> showAuthorizeDeviceDialog(BuildContext context) async =>
    await showWfDialog<bool>(
      context,
      semanticLabel: AppLocalizations.of(context).authorizeDeviceTitle,
      builder: (_) => const AuthorizeDeviceDialog(),
    ) ??
    false;

class AuthorizeDeviceDialog extends ConsumerStatefulWidget {
  const AuthorizeDeviceDialog({super.key});

  @override
  ConsumerState<AuthorizeDeviceDialog> createState() =>
      _AuthorizeDeviceDialogState();
}

class _AuthorizeDeviceDialogState extends ConsumerState<AuthorizeDeviceDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _codeError;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final code = _code.text.replaceAll(RegExp(r'\s'), '');
    setState(() {
      _error = null;
      _codeError = code.isEmpty ? l.authorizeDeviceCodeEmpty : null;
    });
    if (_codeError != null) return;
    setState(() => _busy = true);
    try {
      final auth = ref.read(authApiProvider);
      // Con Quick Connect spento Authorize risponde 401, che farebbe scadere
      // la sessione: prima si chiede se è attivo.
      if (!await auth.quickConnectEnabled()) {
        if (mounted) setState(() => _error = l.quickConnectDisabled);
        return;
      }
      await auth.authorizeQuickConnect(code);
      if (mounted) Navigator.of(context).pop(true);
    } on NotFoundException {
      if (mounted) setState(() => _codeError = l.authorizeDeviceCodeWrong);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error) {
            // nginx mentre Jellyfin si riavvia (502, 503, 504).
            ServerErrorException(:final statusCode)
                when restartGatewayStatuses.contains(statusCode) =>
              l.errorServerUnreachable,
            _ => describeError(l, error),
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.authorizeDeviceTitle,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(l.authorizeDeviceBody),
        const SizedBox(height: 16),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const Key('authorize-device-code'),
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => unawaited(_submit()),
          decoration: InputDecoration(
            labelText: l.authorizeDeviceCode,
            errorText: _codeError,
            errorMaxLines: accountErrorMaxLines,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text(l.accountCancel),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: FilledButton(
                key: const Key('authorize-device-submit'),
                // Il tema fa i FilledButton larghi all'infinito: in una Row
                // servono larghi quanto il testo.
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _busy ? null : () => unawaited(_submit()),
                child: Text(l.authorizeDeviceSubmit),
              ),
            ),
          ],
        ),
      ],
    );
    // Esc e il clic fuori non chiudono la finestra mentre la richiesta è in
    // volo: il dispositivo entrerebbe senza l'avviso.
    return PopScope(
      canPop: !_busy,
      child: SingleChildScrollView(child: content),
    );
  }
}
