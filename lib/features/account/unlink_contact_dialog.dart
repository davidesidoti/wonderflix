import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/social/account_api.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import '../auth/password_login_form.dart';
import 'account_providers.dart';
import 'account_texts.dart';

/// Scollega il contatto di [channel] dopo la password attuale (spec L
/// §9.2). `true` se scollegato.
Future<bool> showUnlinkContactDialog(
    BuildContext context, AccountChannel channel) async {
  final l = AppLocalizations.of(context);
  return await showWfDialog<bool>(
        context,
        semanticLabel: l.accountUnlinkTitle(accountChannelName(l, channel)),
        builder: (_) => UnlinkContactDialog(channel: channel),
      ) ??
      false;
}

/// La password attuale e "Scollega". Come la finestra di collegamento, non
/// si chiude finché la richiesta è in volo.
class UnlinkContactDialog extends ConsumerStatefulWidget {
  const UnlinkContactDialog({super.key, required this.channel});

  final AccountChannel channel;

  @override
  ConsumerState<UnlinkContactDialog> createState() =>
      _UnlinkContactDialogState();
}

class _UnlinkContactDialogState extends ConsumerState<UnlinkContactDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _passwordError;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _passwordError = _error = null;
    });
    try {
      await ref
          .read(accountApiProvider)
          .unlink(widget.channel, password: _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on AccountException catch (error) {
      if (!mounted) return;
      final text = accountFailureText(l, error.failure, widget.channel);
      setState(() {
        if (error.failure == AccountFailure.wrongPassword) {
          _passwordError = text;
        } else {
          _error = text;
        }
      });
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
        Text(l.accountUnlinkTitle(accountChannelName(l, widget.channel)),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Text(l.accountUnlinkBody),
        const SizedBox(height: 16),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const Key('unlink-password'),
          controller: _password,
          autofocus: true,
          obscureText: true,
          onSubmitted: (_) => unawaited(_submit()),
          decoration: InputDecoration(
            labelText: l.accountCurrentPassword,
            helperText: l.accountNoPasswordHint,
            helperMaxLines: accountHelperMaxLines,
            errorText: _passwordError,
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
              key: const Key('unlink-submit'),
              // Il tema fa i FilledButton larghi all'infinito: in una Row
              // servono larghi quanto il testo.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : () => unawaited(_submit()),
              child: Text(l.accountUnlink),
            ),
          ],
        ),
      ],
    );
    // Esc e il clic fuori non chiudono la finestra mentre la richiesta è in
    // volo: lo scollegamento riuscirebbe sul server e la riga resterebbe
    // vecchia.
    return PopScope(canPop: !_busy, child: content);
  }
}
