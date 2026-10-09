import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import '../account/account_texts.dart';
import '../auth/password_login_form.dart';
import 'account_admin_controllers.dart';
import 'account_admin_labels.dart';

/// "Imposta password" per l'utente [userId] (spec L §9.5). `true` se
/// impostata.
Future<bool> showSetPasswordDialog(BuildContext context,
    {required String userId, required String name}) async {
  final l = AppLocalizations.of(context);
  return await showWfDialog<bool>(
        context,
        semanticLabel: l.adminUsersSetPasswordTitle(name),
        builder: (_) => SetPasswordDialog(userId: userId, name: name),
      ) ??
      false;
}

/// Nuova password e conferma, senza quella attuale: Jellyfin la imposta e
/// chiude le sessioni dell'utente. Come le finestre del 18b, non si chiude
/// durante la richiesta.
class SetPasswordDialog extends ConsumerStatefulWidget {
  const SetPasswordDialog(
      {super.key, required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  ConsumerState<SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends ConsumerState<SetPasswordDialog> {
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _newError;
  String? _confirmError;
  String? _error;

  @override
  void dispose() {
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final password = _new.text;
    setState(() {
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
      await ref
          .read(accountUsersControllerProvider.notifier)
          .setPassword(widget.userId, password);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      // Come le altre azioni della scheda: 502/503/504 "non raggiungibile",
      // altrimenti `describeError`. In più, qui il 404 è di Jellyfin:
      // l'utente è stato cancellato nel frattempo (per le chiamate del plugin
      // vuol dire "funzione assente", ed è `accountAdminErrorText` a non
      // dirlo).
      if (mounted) {
        setState(() => _error = error is NotFoundException
            ? l.adminUsersUnknown
            : accountAdminErrorText(l, error, widget.name));
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
        Text(l.adminUsersSetPasswordTitle(widget.name),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(l.adminUsersSetPasswordHint(widget.name),
            style: const TextStyle(color: WfColors.creamMuted)),
        const SizedBox(height: 16),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const Key('set-password-new'),
          controller: _new,
          autofocus: true,
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
          key: const Key('set-password-confirm'),
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
              key: const Key('set-password-submit'),
              // Il tema fa i FilledButton larghi all'infinito: in una Row
              // servono larghi quanto il testo.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : () => unawaited(_submit()),
              child: Text(l.adminUsersSetPassword),
            ),
          ],
        ),
      ],
    );
    // Esc e il clic fuori non la chiudono durante la richiesta: la password
    // cambierebbe senza l'avviso.
    return PopScope(canPop: !_busy, child: content);
  }
}
