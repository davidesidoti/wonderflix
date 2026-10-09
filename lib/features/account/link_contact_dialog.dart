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
import 'resend_code_button.dart';

/// Collega (o sostituisce) il contatto di [channel] (spec L §9.2): i
/// contatti dopo la conferma, `null` se la finestra si chiude prima.
Future<AccountContacts?> showLinkContactDialog(
    BuildContext context, AccountChannel channel) {
  final l = AppLocalizations.of(context);
  return showWfDialog<AccountContacts>(
    context,
    semanticLabel: l.accountLinkTitle(accountChannelName(l, channel)),
    builder: (_) => LinkContactDialog(channel: channel),
  );
}

/// Due passi: il contatto con la password attuale, poi il codice. La
/// password resta in questa finestra fino alla chiusura: "Rimanda il
/// codice" rifà `Start`, che la vuole di nuovo.
class LinkContactDialog extends ConsumerStatefulWidget {
  const LinkContactDialog({super.key, required this.channel});

  final AccountChannel channel;

  @override
  ConsumerState<LinkContactDialog> createState() => _LinkContactDialogState();
}

class _LinkContactDialogState extends ConsumerState<LinkContactDialog> {
  final _target = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();

  /// Il contatto a cui è partito il codice; `null` al primo passo.
  String? _sentTo;
  bool _busy = false;
  String? _targetError;
  String? _passwordError;
  String? _codeError;
  String? _error;

  AccountChannel get _channel => widget.channel;

  @override
  void dispose() {
    _target.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _clearErrors() {
    _targetError = _passwordError = _codeError = _error = null;
  }

  /// Mostra [failure] sotto il campo che lo riguarda, se è sullo schermo;
  /// altrimenti sopra i campi.
  void _show(AccountFailure failure) {
    final text =
        accountFailureText(AppLocalizations.of(context), failure, _channel);
    final firstStep = _sentTo == null;
    setState(() {
      switch (failure) {
        case AccountFailure.invalidTarget || AccountFailure.memberNotFound
            when firstStep:
          _targetError = text;
        case AccountFailure.wrongPassword:
          // La password può essere cambiata altrove dopo il primo passo
          // (il rinvio rifà `Start`, che la controlla): si torna al primo
          // passo, dove c'è il campo, e il codice vecchio non serve più.
          _sentTo = null;
          _code.clear();
          _passwordError = text;
        case AccountFailure.invalidCode when !firstStep:
          _codeError = text;
        case _:
          _error = text;
      }
    });
  }

  /// Manda il codice a [target]. `null` se è partito, altrimenti perché no
  /// (già mostrato).
  Future<AccountFailure?> _send(String target) async {
    final language = Localizations.localeOf(context).languageCode;
    setState(() {
      _busy = true;
      _clearErrors();
    });
    try {
      await ref.read(accountApiProvider).startLink(_channel,
          target: target, password: _password.text, language: language);
      return null;
    } on AccountException catch (error) {
      if (mounted) _show(error.failure);
      return error.failure;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_busy) return;
    final target = _target.text.trim();
    if (target.isEmpty) {
      _show(AccountFailure.invalidTarget);
      return;
    }
    if (await _send(target) == null && mounted) {
      setState(() => _sentTo = target);
    }
  }

  /// "Rimanda il codice". Il conto riparte dopo un 429, perché ogni rinvio
  /// costa un controllo della password; dopo un altro errore si può
  /// riprovare subito.
  Future<bool> _resend() async {
    final failure = await _send(_sentTo!);
    return failure == null || failure == AccountFailure.rateLimited;
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final code = _code.text.trim();
    if (code.isEmpty) {
      _show(AccountFailure.invalidCode);
      return;
    }
    setState(() {
      _busy = true;
      _clearErrors();
    });
    try {
      final contacts =
          await ref.read(accountApiProvider).confirmLink(_channel, code);
      if (mounted) Navigator.of(context).pop(contacts);
    } on AccountException catch (error) {
      if (mounted) _show(error.failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sentTo = _sentTo;
    final discord = _channel == AccountChannel.discord;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.accountLinkTitle(accountChannelName(l, _channel)),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        if (sentTo == null) ...[
          TextField(
            key: const Key('link-target'),
            controller: _target,
            autofocus: true,
            textInputAction: TextInputAction.next,
            keyboardType:
                discord ? TextInputType.text : TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: discord ? l.accountDiscordName : l.accountChannelEmail,
              helperText: discord ? l.accountDiscordNameHint : null,
              helperMaxLines: accountHelperMaxLines,
              errorText: _targetError,
              errorMaxLines: accountErrorMaxLines,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('link-password'),
            controller: _password,
            obscureText: true,
            onSubmitted: (_) => unawaited(_start()),
            decoration: InputDecoration(
              labelText: l.accountCurrentPassword,
              helperText: l.accountNoPasswordHint,
              helperMaxLines: accountHelperMaxLines,
              errorText: _passwordError,
              errorMaxLines: accountErrorMaxLines,
            ),
          ),
        ] else ...[
          Text(discord
              ? l.accountCodeSentDiscord
              : l.accountCodeSentEmail(sentTo)),
          const SizedBox(height: 12),
          TextField(
            key: const Key('link-code'),
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => unawaited(_confirm()),
            decoration: InputDecoration(
              labelText: l.accountCode,
              errorText: _codeError,
              errorMaxLines: accountErrorMaxLines,
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            // Spento mentre un'altra richiesta (la conferma) è in volo.
            child: ResendCodeButton(onResend: _busy ? null : _resend),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(l.accountCancel),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: const Key('link-submit'),
              // Il tema fa i FilledButton larghi all'infinito: in una Row
              // servono larghi quanto il testo.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy
                  ? null
                  : () => unawaited(sentTo == null ? _start() : _confirm()),
              child: Text(
                  sentTo == null ? l.accountSendCode : l.accountConfirm),
            ),
          ],
        ),
      ],
    );
    // Esc e il clic fuori non chiudono la finestra mentre la richiesta è in
    // volo: il collegamento riuscirebbe sul server e la riga resterebbe
    // vecchia.
    return PopScope(canPop: !_busy, child: content);
  }
}
