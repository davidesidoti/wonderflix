import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/social/plugin_admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_menus.dart';
import '../auth/session_controller.dart';
import 'account_admin_controllers.dart';
import 'account_admin_labels.dart';
import 'admin_confirm_dialog.dart';
import 'admin_widgets.dart';
import 'set_password_dialog.dart';

/// Diametro dell'avatar di una riga.
const _avatarSize = 28.0;

/// Larghezza del posto del menu: le righe senza menu restano allineate.
const _menuWidth = 40.0;

/// La scheda Utenti (spec L §9.5): ogni utente con i suoi contatti per il
/// recupero e le azioni dell'admin.
class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key});

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(accountUsersControllerProvider);
    final users = data.value;
    if (users == null) {
      final error = data.error;
      if (error == null) return const LoadingView();
      return ErrorView(
        error: error,
        onRetry: () => unawaited(
            ref.read(accountUsersControllerProvider.notifier).refresh()),
      );
    }
    final me = ref.watch(sessionControllerProvider.select(
        (s) => s is SessionSignedIn ? jellyfinIdKey(s.user.id) : null));
    final updatedAt = data.updatedAt;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
      children: [
        if (data.stale && updatedAt != null)
          AdminStaleNote(updatedAt: updatedAt),
        if (users.isEmpty)
          AdminEmptyText(text: l.adminUsersEmpty)
        else
          for (final user in users)
            AccountUserRow(
              key: ValueKey('user-${user.id}'),
              user: user,
              isMe: jellyfinIdKey(user.id) == me,
            ),
      ],
    );
  }
}

/// Le azioni del menu di una riga.
enum UserAction { setPassword, sendRecovery, unlink }

/// Le azioni per [user] (spec L §9.5): "Imposta password" non sulla propria
/// riga (per la propria Jellyfin vuole la password attuale, e c'è "Cambia
/// password" in Impostazioni); il codice non agli admin né ai disattivati, e
/// solo con un contatto; lo scollegamento solo con un contatto.
List<UserAction> userActions(AdminAccountUser user, {required bool isMe}) => [
      if (!isMe) UserAction.setPassword,
      if (!user.isAdmin && user.enabled && user.hasContacts)
        UserAction.sendRecovery,
      if (user.hasContacts) UserAction.unlink,
    ];

/// Un utente: avatar, nome, etichette, contatti e il menu delle azioni.
class AccountUserRow extends ConsumerStatefulWidget {
  const AccountUserRow({super.key, required this.user, required this.isMe});

  final AdminAccountUser user;

  /// La riga dell'admin che guarda.
  final bool isMe;

  @override
  ConsumerState<AccountUserRow> createState() => _AccountUserRowState();
}

class _AccountUserRowState extends ConsumerState<AccountUserRow> {
  /// Un'azione in corso: intanto il menu è spento.
  bool _busy = false;

  AdminAccountUser get _user => widget.user;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPassword() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final done =
        await showSetPasswordDialog(context, userId: _user.id, name: _user.name);
    if (done && mounted) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.adminUsersPasswordSet(_user.name))));
    }
  }

  Future<void> _sendRecovery() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final confirmed = await showAdminConfirmDialog(
      context,
      title: l.adminUsersSendRecovery,
      message: l.adminUsersSendRecoveryConfirm(_user.name),
      confirmLabel: l.adminSend,
    );
    if (!confirmed || !mounted) return;
    // Non `final`: nel `catch` si assegna di nuovo, e Dart non sa che il
    // `try` non ha già assegnato.
    String text;
    try {
      final channels = await ref
          .read(accountUsersControllerProvider.notifier)
          .sendRecoveryCode(_user.id, language: language);
      text = recoverySentLabel(l, channels);
    } on Object catch (error) {
      text = accountAdminErrorText(l, error, _user.name);
    }
    // Come `AdminActionButton`: con la scheda cambiata nel frattempo, niente
    // avviso.
    if (mounted) messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _unlink() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showAdminConfirmDialog(
      context,
      title: l.adminUsersUnlink,
      message: l.adminUsersUnlinkConfirm(_user.name),
      confirmLabel: l.accountUnlink,
    );
    if (!confirmed || !mounted) return;
    String text;
    try {
      await ref
          .read(accountUsersControllerProvider.notifier)
          .unlinkContacts(_user.id);
      text = l.adminUsersUnlinked(_user.name);
    } on Object catch (error) {
      text = accountAdminErrorText(l, error, _user.name);
    }
    if (mounted) messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  void _select(UserAction action) => unawaited(_run(switch (action) {
        UserAction.setPassword => _setPassword,
        UserAction.sendRecovery => _sendRecovery,
        UserAction.unlink => _unlink,
      }));

  String _actionLabel(AppLocalizations l, UserAction action) =>
      switch (action) {
        UserAction.setPassword => l.adminUsersSetPassword,
        UserAction.sendRecovery => l.adminUsersSendRecovery,
        UserAction.unlink => l.adminUsersUnlink,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final user = _user;
    final actions = userActions(user, isMe: widget.isMe);
    final discord = user.discordName;
    final email = user.maskedEmail;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          UserAvatar.lookup(
              userId: user.id, name: user.name, size: _avatarSize),
          const SizedBox(width: 10),
          Flexible(
            child: Text(user.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (user.isAdmin) ...[
            const SizedBox(width: 8),
            _Badge(text: l.adminUsersAdmin),
          ],
          if (!user.enabled) ...[
            const SizedBox(width: 8),
            _Badge(text: l.adminUsersDisabled),
          ],
          const Spacer(),
          _ContactIcon(
            icon: LucideIcons.messageCircle,
            linked: discord != null,
            tooltip: discord == null
                ? l.adminUsersDiscordNone
                : l.adminUsersDiscordLinked(discord),
          ),
          const SizedBox(width: 8),
          _ContactIcon(
            icon: LucideIcons.mail,
            linked: email != null,
            tooltip: email == null
                ? l.adminUsersEmailNone
                : l.adminUsersEmailLinked(email),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: _menuWidth,
            child: actions.isEmpty
                ? null
                : PopupMenuButton<UserAction>(
                    key: Key('user-menu-${user.id}'),
                    tooltip: l.adminUsersActions,
                    enabled: !_busy,
                    icon: const Icon(LucideIcons.ellipsisVertical,
                        size: 18, color: WfColors.creamMuted),
                    popUpAnimationStyle: wfPopUpAnimation(context),
                    onSelected: _select,
                    itemBuilder: (context) => [
                      for (final action in actions)
                        PopupMenuItem<UserAction>(
                            value: action,
                            child: Text(_actionLabel(l, action))),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// "Admin", "Disattivato".
class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: WfColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
      );
}

/// L'icona di un canale: oro se collegato, grigia se no; il tooltip dice il
/// contatto (l'email è mascherata dal plugin).
class _ContactIcon extends StatelessWidget {
  const _ContactIcon(
      {required this.icon, required this.linked, required this.tooltip});

  final IconData icon;
  final bool linked;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Icon(icon,
            size: 18, color: linked ? WfColors.gold : WfColors.creamMuted),
      );
}
