import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/error_text.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/tv_text_field_frame.dart';
import 'session_controller.dart';

class PasswordLoginForm extends ConsumerStatefulWidget {
  const PasswordLoginForm({
    super.key,
    this.initialUsername,
    this.onForgotPassword,
    this.onNotYou,
  });

  /// Il nome già scritto ("Accedi di nuovo", spec K §9.3): il fuoco va alla
  /// password.
  final String? initialUsername;

  /// "Password dimenticata?" (spec L §9.3), con il nome scritto; senza, il
  /// link non c'è.
  final ValueChanged<String>? onForgotPassword;

  /// "Non sei tu?" accanto all'etichetta del nome (spec §9.2); senza, il
  /// link non c'è.
  final VoidCallback? onNotYou;

  @override
  ConsumerState<PasswordLoginForm> createState() => _PasswordLoginFormState();
}

class _PasswordLoginFormState extends ConsumerState<PasswordLoginForm> {
  late final _username = TextEditingController(text: widget.initialUsername);
  final _password = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _passwordFrame = GlobalKey<TvTextFieldFrameState>();
  bool _busy = false;
  bool _obscured = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .loginWithPassword(_username.text, _password.text);
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final supportUrl = ref.watch(appConfigProvider).supportUrl;
    // Sulla TV il fuoco parte dal telecomando: un campo con `autofocus`
    // aprirebbe subito la tastiera.
    final tv = FormFactor.of(context).tv;
    const labelStyle = TextStyle(
      color: WfColors.creamMuted,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
    );
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(text, style: labelStyle),
    );
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            ErrorBanner(_error!),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: label(l.loginUsername)),
              if (widget.onNotYou case final onNotYou?)
                // Fuori dalla TV alto quanto l'etichetta: le due righe
                // restano uguali. In TV la misura piena, per il focus.
                Padding(
                  padding: EdgeInsets.only(bottom: tv ? 0 : 7),
                  child: TextButton(
                    key: const Key('login-not-you'),
                    onPressed: onNotYou,
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      tapTargetSize: tv
                          ? null
                          : MaterialTapTargetSize.shrinkWrap,
                      minimumSize: tv ? null : Size.zero,
                      padding: tv
                          ? null
                          : const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: Text(l.loginNotYou),
                  ),
                ),
            ],
          ),
          TvTextFieldFrame(
            focusNode: _usernameFocus,
            child: TextField(
              key: const Key('login-username'),
              controller: _username,
              focusNode: _usernameFocus,
              autofocus: !tv && widget.initialUsername == null,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              // Sulla TV "Avanti" della tastiera apre subito la password.
              onSubmitted: tv
                  ? (_) => _passwordFrame.currentState?.startTyping()
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          label(l.loginPassword),
          TvTextFieldFrame(
            key: _passwordFrame,
            focusNode: _passwordFocus,
            child: TextField(
              key: const Key('login-password'),
              controller: _password,
              focusNode: _passwordFocus,
              autofocus: !tv && widget.initialUsername != null,
              obscureText: _obscured,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => unawaited(_submit()),
              // In TV niente occhio: il campo è in cornice.
              decoration: InputDecoration(
                suffixIcon: tv
                    ? null
                    : IconButton(
                        key: const Key('login-password-eye'),
                        tooltip: _obscured
                            ? l.loginShowPassword
                            : l.loginHidePassword,
                        icon: Icon(
                          _obscured ? LucideIcons.eye : LucideIcons.eyeOff,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _obscured = !_obscured),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('login-submit'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: WfColors.bg,
                    ),
                  )
                : Text(l.loginSubmit),
          ),
          if (widget.onForgotPassword != null || supportUrl != null) ...[
            const SizedBox(height: 12),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.onForgotPassword case final onForgot?)
                  TextButton(
                    key: const Key('login-forgot'),
                    // Spento durante un accesso: il recupero smonterebbe il
                    // modulo e un errore o l'ingresso andrebbero persi.
                    onPressed: _busy ? null : () => onForgot(_username.text),
                    child: Text(l.loginForgotPassword),
                  ),
                if (supportUrl != null)
                  // In TV non c'è un browser da aprire: solo il testo.
                  if (tv)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(l.loginAskAdmin,
                          style: const TextStyle(color: WfColors.creamMuted)),
                    )
                  else
                    TextButton(
                      onPressed: () => unawaited(launchUrl(supportUrl)),
                      child: Text(l.loginContactAdmin),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: WfColors.error.withValues(alpha: 0.15),
        border: Border.all(color: WfColors.error.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(message,
          style: const TextStyle(color: Color(0xFFF0B4AD), fontSize: 12.5)),
    );
  }
}
