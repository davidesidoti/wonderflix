import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/error_text.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'session_controller.dart';

class PasswordLoginForm extends ConsumerStatefulWidget {
  const PasswordLoginForm({super.key});

  @override
  ConsumerState<PasswordLoginForm> createState() => _PasswordLoginFormState();
}

class _PasswordLoginFormState extends ConsumerState<PasswordLoginForm> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const Key('login-username'),
          controller: _username,
          autofocus: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(hintText: l.loginUsername),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('login-password'),
          controller: _password,
          obscureText: true,
          onSubmitted: (_) => unawaited(_submit()),
          decoration: InputDecoration(hintText: l.loginPassword),
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
                      strokeWidth: 2, color: WfColors.bg),
                )
              : Text(l.loginSubmit),
        ),
        if (supportUrl != null) ...[
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l.loginForgotPassword,
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12.5)),
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
