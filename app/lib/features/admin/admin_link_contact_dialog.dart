import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/social/plugin_admin_api.dart';
import '../../core/social/plugin_admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import '../account/account_texts.dart';
import 'account_admin_controllers.dart';
import 'account_admin_labels.dart';
import 'admin_providers.dart';

/// "Associa Discord" per l'utente [userId] (spec §5.1). `true` se salvato.
Future<bool> showAdminLinkDiscordDialog(
  BuildContext context, {
  required String userId,
  required String name,
}) =>
    _show(context, userId: userId, name: name, discord: true);

/// "Associa email" per l'utente [userId]. `true` se salvato.
Future<bool> showAdminLinkEmailDialog(
  BuildContext context, {
  required String userId,
  required String name,
}) =>
    _show(context, userId: userId, name: name, discord: false);

Future<bool> _show(
  BuildContext context, {
  required String userId,
  required String name,
  required bool discord,
}) async {
  final l = AppLocalizations.of(context);
  return await showWfDialog<bool>(
        context,
        semanticLabel: discord
            ? l.adminUsersLinkDiscordTitle(name)
            : l.adminUsersLinkEmailTitle(name),
        builder: (_) =>
            _AdminLinkDialog(userId: userId, name: name, discord: discord),
      ) ??
      false;
}

/// L'admin scrive il contatto, senza codice: il plugin lo salva subito.
/// Discord prima cerca il membro nel server e mostra chi è, poi lo associa.
/// Come `SetPasswordDialog`, non si chiude durante la richiesta.
class _AdminLinkDialog extends ConsumerStatefulWidget {
  const _AdminLinkDialog({
    required this.userId,
    required this.name,
    required this.discord,
  });

  final String userId;
  final String name;
  final bool discord;

  @override
  ConsumerState<_AdminLinkDialog> createState() => _AdminLinkDialogState();
}

class _AdminLinkDialogState extends ConsumerState<_AdminLinkDialog> {
  final _field = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Il membro trovato da "Cerca": c'è, e il pulsante dice "Associa".
  AdminDiscordMember? _member;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  String _errorText(AppLocalizations l, Object error) =>
      switch (pluginErrorCode(error)) {
        'InvalidTarget' => widget.discord
            ? l.accountErrorInvalidDiscordName
            : l.accountErrorInvalidEmail,
        'MemberNotFound' => l.adminUsersMemberNotFound,
        'ChannelOff' => l.adminUsersChannelOff,
        _ => accountAdminErrorText(l, error, widget.name),
      };

  /// Un nome diverso da quello cercato: anteprima ed errore non valgono più.
  void _changed(String _) {
    if (_member != null || _error != null) {
      setState(() => _member = _error = null);
    }
  }

  Future<void> _submit() async {
    final text = _field.text.trim();
    if (_busy || text.isEmpty) return;
    final l = AppLocalizations.of(context);
    final users = ref.read(accountUsersControllerProvider.notifier);
    final member = _member;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!widget.discord) {
        await users.setEmail(widget.userId, text);
      } else if (member == null) {
        final found =
            await ref.read(pluginAdminApiProvider).lookupDiscordMember(text);
        if (mounted) setState(() => _member = found);
        return;
      } else {
        await users.setDiscord(widget.userId, member);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(l, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final discord = widget.discord;
    final member = _member;
    final displayName = member?.displayName;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          discord
              ? l.adminUsersLinkDiscordTitle(widget.name)
              : l.adminUsersLinkEmailTitle(widget.name),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('admin-link-field'),
          controller: _field,
          autofocus: true,
          keyboardType:
              discord ? TextInputType.text : TextInputType.emailAddress,
          onChanged: _changed,
          onSubmitted: (_) => unawaited(_submit()),
          decoration: InputDecoration(
            labelText: discord ? l.accountDiscordName : l.accountChannelEmail,
            helperText: discord ? l.accountDiscordNameHint : null,
            helperMaxLines: accountHelperMaxLines,
            errorText: _error,
            errorMaxLines: accountErrorMaxLines,
          ),
        ),
        if (member != null) ...[
          const SizedBox(height: 12),
          Text('@${member.username}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (displayName != null)
            Text(displayName,
                style: const TextStyle(color: WfColors.creamMuted)),
        ],
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
                key: const Key('admin-link-submit'),
                // Il tema fa i FilledButton larghi all'infinito: in una Row
                // servono larghi quanto il testo.
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _busy ? null : () => unawaited(_submit()),
                child: Text(discord && member == null
                    ? l.adminUsersLinkSearch
                    : l.adminUsersLinkSubmit),
              ),
            ),
          ],
        ),
      ],
    );
    // Esc e il clic fuori non la chiudono durante la richiesta: il contatto
    // cambierebbe senza l'avviso.
    return PopScope(
      canPop: !_busy,
      child: SingleChildScrollView(child: content),
    );
  }
}
