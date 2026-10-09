import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/error_text.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/social/account_api.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../account/account_providers.dart';
import '../account/account_texts.dart';
import '../account/field_focus.dart';
import '../account/resend_code_button.dart';
import 'password_login_form.dart';
import 'session_controller.dart';

const _mutedStyle = TextStyle(color: WfColors.creamMuted, fontSize: 12.5);

/// "Password dimenticata?" (spec L §9.3), al posto del modulo di accesso:
/// il codice ai contatti collegati, poi la password nuova e l'accesso.
class RecoveryPanel extends ConsumerStatefulWidget {
  const RecoveryPanel({super.key, this.initialUsername, required this.onBack});

  /// Il nome scritto nel modulo di accesso.
  final String? initialUsername;

  /// Torna al modulo di accesso, con il nome scritto qui.
  final ValueChanged<String> onBack;

  @override
  ConsumerState<RecoveryPanel> createState() => _RecoveryPanelState();
}

class _RecoveryPanelState extends ConsumerState<RecoveryPanel> {
  late final _username = TextEditingController(text: widget.initialUsername);
  final _code = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  final _codeFocus = FocusNode();

  /// Il fuoco di "ACCEDI" nella vista "password cambiata" ([_changedTo]).
  final _signInFocus = FocusNode();

  /// Il nome per cui è partito il codice; `null` al primo passo.
  String? _sentFor;

  /// Il plugin non ha il recupero (404): assente o vecchio (spec L §9.1).
  bool _unavailable = false;

  /// La password nuova, già cambiata sul server; `null` finché il cambio non
  /// riesce. Con questa il secondo passo cambia vista: niente campi (una
  /// password riscritta sarebbe ignorata) né "Rimanda" (il codice è già
  /// usato), solo l'avviso e "ACCEDI", che riprova l'accesso con questa.
  String? _changedTo;

  /// Il codice c'è già (per esempio mandato dall'admin, spec L §9.5): il
  /// secondo passo dice di scriverlo, senza averne chiesto uno.
  bool _haveCode = false;
  bool _busy = false;
  String? _usernameError;
  String? _codeError;
  String? _newError;
  String? _confirmError;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _code.dispose();
    _new.dispose();
    _confirm.dispose();
    _codeFocus.dispose();
    _signInFocus.dispose();
    super.dispose();
  }

  void _clearErrors() {
    _usernameError = _codeError = _newError = _confirmError = _error = null;
  }

  /// Chiede il codice per [username]. `null` se la richiesta è passata (la
  /// risposta è la stessa che l'account esista o no), altrimenti l'errore,
  /// già mostrato.
  Future<AccountFailure?> _requestCode(String username) async {
    final l = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    setState(() {
      _busy = true;
      _clearErrors();
    });
    try {
      await ref
          .read(accountApiProvider)
          .startRecovery(username: username, language: language);
      return null;
    } on AccountException catch (error) {
      if (mounted) {
        setState(() {
          switch (error.failure) {
            case AccountFailure.unavailable:
              _unavailable = true;
            case AccountFailure.rateLimited:
              _error = l.accountErrorRateLimited;
            case AccountFailure.network:
              _error = l.errorServerUnreachable;
            case _:
              _error = l.errorGeneric;
          }
        });
      }
      return error.failure;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_busy) return;
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() =>
          _usernameError = AppLocalizations.of(context).recoveryNameNeeded);
      return;
    }
    if (await _requestCode(username) == null && mounted) {
      setState(() => _sentFor = username);
    }
  }

  /// "Ho già un codice" (decisione 8 del piano 18c): il secondo passo con il
  /// nome scritto, senza `Start`, che manderebbe un codice nuovo al posto di
  /// quello che l'utente ha già.
  void _haveCodeAlready() {
    if (_busy) return;
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() =>
          _usernameError = AppLocalizations.of(context).recoveryNameNeeded);
      return;
    }
    setState(() {
      _clearErrors();
      _haveCode = true;
      _sentFor = username;
    });
  }

  /// "Rimanda il codice": il conto riparte se il codice è partito, e anche
  /// dopo un 429 (si aspetta comunque); dopo un altro errore si può
  /// riprovare subito.
  Future<bool> _resend() async {
    final failure = await _requestCode(_sentFor!);
    // Il codice nuovo sostituisce il vecchio sul server: con quello vecchio
    // nel campo, "Cambia password" darebbe "Codice non valido o scaduto".
    // Dopo un errore nessun codice è partito, e quello scritto vale ancora.
    // Lo stesso vale per quello che l'utente aveva già (`_haveCode`, per
    // esempio dell'admin): non è più "quello che hai ricevuto".
    if (failure == null && mounted) {
      setState(() {
        _code.clear();
        _haveCode = false;
      });
    }
    return failure == null || failure == AccountFailure.rateLimited;
  }

  Future<void> _complete() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final username = _sentFor!;
    final changedTo = _changedTo;
    if (changedTo != null) {
      // Il cambio è già riuscito e l'accesso no: "ACCEDI" riprova solo
      // l'accesso, con la password già cambiata (il codice è usato).
      setState(() {
        _busy = true;
        _clearErrors();
      });
      await _signIn(l, username, changedTo);
      return;
    }
    final code = _code.text.trim();
    final password = _new.text;
    setState(() {
      _clearErrors();
      if (code.isEmpty) _codeError = l.accountErrorInvalidCode;
      if (password.length < accountMinPasswordLength) {
        _newError = l.accountPasswordTooShort;
      } else if (_confirm.text != password) {
        _confirmError = l.accountPasswordsDiffer;
      }
    });
    if (_codeError != null || _newError != null || _confirmError != null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(accountApiProvider).completeRecovery(
          username: username,
          code: code,
          newPassword: password,
          language: language);
    } on AccountException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          switch (error.failure) {
            // Il 404 qui arriva solo con "Ho già un codice", che non passa da
            // `Start`: plugin assente o vecchio, come al primo passo.
            case AccountFailure.unavailable:
              _unavailable = true;
            case AccountFailure.invalidCode:
              _codeError = l.accountErrorInvalidCode;
              // Invio nell'ultimo campo ha tolto il fuoco: torna al codice,
              // selezionato per riscriverlo.
              focusAndSelectAfterFrame(this, _codeFocus, _code);
            case AccountFailure.weakPassword:
              _newError = l.accountPasswordTooShort;
            case AccountFailure.rateLimited:
              _error = l.recoveryTooMany;
            // Senza rete il codice può essere ancora buono.
            case AccountFailure.network:
              _error = l.errorServerUnreachable;
            // Anche il 500 di Jellyfin: il codice è già usato (spec L §11).
            case _:
              _error = l.recoveryFailed;
          }
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _changedTo = password);
    await _signIn(l, username, password);
  }

  /// Entra con la password nuova (spec L §9.3): il profilo salvato prende il
  /// token nuovo. Se l'accesso non riesce, l'errore resta qui e "ACCEDI"
  /// riprova solo l'accesso ([_changedTo]).
  Future<void> _signIn(
      AppLocalizations l, String username, String password) async {
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .loginWithPassword(username, password);
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeError(l, error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _focusSignIn();
      }
    }
  }

  /// Dà il fuoco a "ACCEDI": i campi sono spariti con il cambio, e durante
  /// l'accesso il pulsante è spento e il fuoco cade. Si aspetta il frame in
  /// cui si riaccende (un `autofocus` non basta: il pulsante nasce spento).
  void _focusSignIn() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _signInFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final supportUrl = ref.watch(appConfigProvider).supportUrl;
    final sentFor = _sentFor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('recovery-back'),
            // Spento durante una richiesta: tornando indietro a metà cambio
            // la password cambierebbe senza l'accesso e senza un avviso.
            onPressed: _busy ? null : () => widget.onBack(_username.text),
            icon: const Icon(LucideIcons.arrowLeft, size: 16),
            label: Text(l.recoveryBack),
          ),
        ),
        const SizedBox(height: 8),
        Text(l.recoveryTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        if (_unavailable)
          Text(l.recoveryUnavailable)
        else if (sentFor == null) ...[
          TextField(
            key: const Key('recovery-username'),
            controller: _username,
            autofocus: true,
            onSubmitted: (_) => unawaited(_start()),
            decoration: InputDecoration(
                hintText: l.loginUsername,
                errorText: _usernameError,
                errorMaxLines: accountErrorMaxLines),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('recovery-send'),
            onPressed: _busy ? null : () => unawaited(_start()),
            child: Text(l.accountSendCode),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('recovery-have-code'),
              onPressed: _busy ? null : _haveCodeAlready,
              child: Text(l.recoveryHaveCode),
            ),
          ),
        ] else if (_changedTo != null) ...[
          Text(l.recoveryChanged, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('recovery-submit'),
            focusNode: _signInFocus,
            onPressed: _busy ? null : () => unawaited(_complete()),
            child: Text(l.loginSubmit),
          ),
        ] else ...[
          Text(_haveCode ? l.recoveryEnterCode : l.recoveryCodeSent,
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            key: const Key('recovery-code'),
            controller: _code,
            focusNode: _codeFocus,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
                hintText: l.accountCode,
                errorText: _codeError,
                errorMaxLines: accountErrorMaxLines),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('recovery-new'),
            controller: _new,
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
                hintText: l.accountNewPassword,
                errorText: _newError,
                errorMaxLines: accountErrorMaxLines),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('recovery-confirm'),
            controller: _confirm,
            obscureText: true,
            onSubmitted: (_) => unawaited(_complete()),
            decoration: InputDecoration(
                hintText: l.accountConfirmPassword,
                errorText: _confirmError,
                errorMaxLines: accountErrorMaxLines),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('recovery-submit'),
            onPressed: _busy ? null : () => unawaited(_complete()),
            child: Text(l.settingsChangePassword),
          ),
          Align(
            alignment: Alignment.centerLeft,
            // Spento mentre il cambio è in volo: un codice nuovo
            // sostituirebbe quello che si sta usando.
            child: ResendCodeButton(onResend: _busy ? null : _resend),
          ),
        ],
        if (supportUrl != null) ...[
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!_unavailable) Text(l.recoveryNoContact, style: _mutedStyle),
              TextButton(
                onPressed: () => unawaited(launchUrl(supportUrl)),
                child: Text(l.loginContactAdmin),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
