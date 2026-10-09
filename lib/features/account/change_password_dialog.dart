import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/error_text.dart';
import '../../app/providers.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import '../auth/password_login_form.dart';
import '../auth/session_controller.dart';
import 'account_texts.dart';

/// Cambia la password dell'utente aperto (spec L §9.2). `true` se è
/// cambiata.
Future<bool> showChangePasswordDialog(BuildContext context) async =>
    await showWfDialog<bool>(
      context,
      semanticLabel: AppLocalizations.of(context).settingsChangePassword,
      builder: (_) => const ChangePasswordDialog(),
    ) ??
    false;

/// Password attuale (vuota per un account senza), nuova e conferma.
/// Jellyfin chiude le altre sessioni dell'utente e tiene questa: il profilo
/// di questo PC resta dentro.
class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _currentError;
  String? _newError;
  String? _confirmError;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionControllerProvider);
    if (session is! SessionSignedIn) return;
    final password = _new.text;
    setState(() {
      _currentError = null;
      _error = null;
      _newError = password.length < accountMinPasswordLength
          ? l.accountPasswordTooShort
          : null;
      _confirmError = _newError == null && _confirm.text != password
          ? l.accountPasswordsDiffer
          : null;
    });
    if (_newError != null || _confirmError != null) return;
    setState(() => _busy = true);
    try {
      await ref.read(authApiProvider).changePassword(session.user.id,
          currentPassword: _current.text, newPassword: password);
      if (mounted) Navigator.of(context).pop(true);
    } on ForbiddenException {
      if (mounted) setState(() => _currentError = l.accountWrongPassword);
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeError(l, error));
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
        Text(l.settingsChangePassword,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const Key('change-password-current'),
          controller: _current,
          autofocus: true,
          obscureText: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l.accountCurrentPassword,
            helperText: l.accountNoPasswordHint,
            helperMaxLines: accountHelperMaxLines,
            errorText: _currentError,
            errorMaxLines: accountErrorMaxLines,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('change-password-new'),
          controller: _new,
          obscureText: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l.accountNewPassword,
            errorText: _newError,
            errorMaxLines: accountErrorMaxLines,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('change-password-confirm'),
          controller: _confirm,
          obscureText: true,
          onSubmitted: (_) => unawaited(_submit()),
          decoration: InputDecoration(
            labelText: l.accountConfirmPassword,
            errorText: _confirmError,
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
            FilledButton(
              key: const Key('change-password-submit'),
              // Il tema fa i FilledButton larghi all'infinito: in una Row
              // servono larghi quanto il testo.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : () => unawaited(_submit()),
              child: Text(l.settingsChangePassword),
            ),
          ],
        ),
      ],
    );
    // Esc e il clic fuori non chiudono la finestra mentre la richiesta è in
    // volo: la password cambierebbe senza l'avviso.
    return PopScope(canPop: !_busy, child: content);
  }
}
