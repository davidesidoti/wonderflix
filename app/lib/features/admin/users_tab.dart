import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/social/plugin_admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_menus.dart';
import '../auth/session_controller.dart';
import '../social/social_providers.dart';
import 'account_admin_controllers.dart';
import 'account_admin_labels.dart';
import 'account_recovery_card.dart';
import 'admin_confirm_dialog.dart';
import 'admin_kit.dart';
import 'admin_link_contact_dialog.dart';
import 'admin_widgets.dart';
import 'set_password_dialog.dart';

/// Diametro dell'avatar di una tessera.
const _avatarSize = 40.0;

/// Lato delle caselline dei contatti.
const _contactBoxSize = 20.0;

/// Spazio fra le tessere, in orizzontale e in verticale.
const _tileGap = 8.0;

/// Larghezza del posto del menu: le righe senza menu restano allineate.
const _menuWidth = 40.0;

/// Lato dello spinner che prende il posto dell'icona del menu mentre la riga
/// lavora.
const _spinnerSize = 16.0;

/// La scheda Utenti (spec L §9.5): ogni utente con i suoi contatti per il
/// recupero e le azioni dell'admin.
class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key, this.header});

  /// La striscia del server, nel layout stretto: scorre con l'elenco.
  final Widget? header;

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
      if (error == null) {
        return adminTabState(context, widget.header, const LoadingView());
      }
      return adminTabState(
        context,
        widget.header,
        ErrorView(
          error: error,
          onRetry: () => unawaited(
              ref.read(accountUsersControllerProvider.notifier).refresh()),
        ),
      );
    }
    final me = ref.watch(sessionControllerProvider.select(
        (s) => s is SessionSignedIn ? jellyfinIdKey(s.user.id) : null));
    final updatedAt = data.updatedAt;
    // Largo: due tessere per riga; stretto: una. Righe e non `Wrap`, così la
    // lista resta pigra (e le tessere fuori vista si smontano).
    final perRow = FormFactor.of(context).compact ? 1 : 2;
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
          adminSideMargin(context), 0, adminSideMargin(context), 40),
      children: [
        if (widget.header case final header?)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: header),
        if (data.stale && updatedAt != null)
          AdminStaleNote(updatedAt: updatedAt),
        AdminTabTitle(title: l.adminTabUsers, count: users.length),
        const SizedBox(height: 14),
        const AccountRecoveryBand(),
        if (users.isEmpty)
          AdminEmptyText(text: l.adminUsersEmpty)
        else
          for (var i = 0; i < users.length; i += perRow)
            Padding(
              padding: const EdgeInsets.only(bottom: _tileGap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = i; j < i + perRow; j++) ...[
                    if (j > i) const SizedBox(width: _tileGap),
                    Expanded(
                      child: j < users.length
                          ? AccountUserRow(
                              key: ValueKey('user-${users[j].id}'),
                              user: users[j],
                              isMe: jellyfinIdKey(users[j].id) == me,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}

/// Le azioni del menu di una riga.
enum UserAction { setPassword, sendRecovery, linkDiscord, linkEmail, unlink }

/// Le azioni per [user] (spec L §9.5): "Imposta password" non sulla propria
/// riga (per la propria Jellyfin vuole la password attuale, e c'è "Cambia
/// password" in Impostazioni); il codice non agli admin né ai disattivati, e
/// solo con un contatto; lo scollegamento solo con un contatto. Le
/// associazioni per tutti, con il canale acceso (spec §5.1): sostituiscono
/// il contatto che c'è.
List<UserAction> userActions(AdminAccountUser user,
        {required bool isMe,
        bool canLinkDiscord = false,
        bool canLinkEmail = false}) =>
    [
      if (!isMe) UserAction.setPassword,
      if (!user.isAdmin && user.enabled && user.hasContacts)
        UserAction.sendRecovery,
      if (canLinkDiscord) UserAction.linkDiscord,
      if (canLinkEmail) UserAction.linkEmail,
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

class _AccountUserRowState extends ConsumerState<AccountUserRow>
    with AutomaticKeepAliveClientMixin {
  /// Un'azione in corso: intanto il menu è spento.
  bool _busy = false;

  /// La `ListView` smonta le righe fuori vista: se l'admin scorre mentre
  /// un'azione è in corso (il codice è già partito, o la password sta
  /// cambiando), la riga sparirebbe con il suo avviso, e quella nuova avrebbe
  /// il menu acceso (si potrebbe rimandare, e il secondo codice sostituisce
  /// il primo). Finché l'azione dura la riga resta.
  @override
  bool get wantKeepAlive => _busy;

  AdminAccountUser get _user => widget.user;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    updateKeepAlive();
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        updateKeepAlive();
      }
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

  Future<void> _link({required bool discord}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final done = discord
        ? await showAdminLinkDiscordDialog(context,
            userId: _user.id, name: _user.name)
        : await showAdminLinkEmailDialog(context,
            userId: _user.id, name: _user.name);
    if (done && mounted) {
      messenger.showSnackBar(SnackBar(
          content: Text(discord
              ? l.adminUsersDiscordLinkedTo(_user.name)
              : l.adminUsersEmailLinkedTo(_user.name))));
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
        UserAction.linkDiscord => () => _link(discord: true),
        UserAction.linkEmail => () => _link(discord: false),
        UserAction.unlink => _unlink,
      }));

  String _actionLabel(AppLocalizations l, UserAction action) =>
      switch (action) {
        UserAction.setPassword => l.adminUsersSetPassword,
        UserAction.sendRecovery => l.adminUsersSendRecovery,
        UserAction.linkDiscord => l.adminUsersLinkDiscord,
        UserAction.linkEmail => l.adminUsersLinkEmail,
        UserAction.unlink => l.adminUsersUnlink,
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);
    final user = _user;
    // Lo stato dei canali si legge solo con un plugin che sa associare; finché
    // non c'è (in lettura o in errore) le voci mancano.
    final canLink = ref.watch(
        socialAvailabilityProvider.select((f) => f.accountAdminLink));
    final status =
        canLink ? ref.watch(accountAdminControllerProvider).value : null;
    final actions = userActions(user,
        isMe: widget.isMe,
        canLinkDiscord: status?.discord.configured == true,
        canLinkEmail: status?.email.configured == true);
    final discord = user.discordName;
    final email = user.maskedEmail;
    final tile = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WfColors.surface,
        border: Border.all(color: WfColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          UserAvatar.lookup(
              userId: user.id, name: user.name, size: _avatarSize),
          const SizedBox(width: 10),
          // Nome ed etichette prendono tutto lo spazio che resta: un nome
          // lungo si tronca solo quando non c'è più posto.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(user.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (user.isAdmin) ...[
                      const SizedBox(width: 8),
                      _Badge(
                          text: l.adminUsersAdmin,
                          color: WfColors.gold,
                          background: WfColors.gold.withValues(alpha: 0.18)),
                    ],
                    if (!user.enabled) ...[
                      const SizedBox(width: 8),
                      _Badge(
                          text: l.adminUsersDisabled,
                          color: WfColors.creamMuted,
                          background: WfColors.cream.withValues(alpha: 0.08)),
                    ],
                  ],
                ),
                // Senza contatti non può recuperare la password da solo.
                if (!user.isAdmin && user.enabled && !user.hasContacts)
                  Text(l.adminUsersNoContact,
                      style:
                          const TextStyle(color: WfColors.gold, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _ContactBox(
            label: 'D',
            linked: discord != null,
            tooltip: discord == null
                ? l.adminUsersDiscordNone
                : l.adminUsersDiscordLinked(discord),
          ),
          const SizedBox(width: 6),
          _ContactBox(
            label: '@',
            linked: email != null,
            tooltip: email == null
                ? l.adminUsersEmailNone
                : l.adminUsersEmailLinked(email),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: FormFactor.of(context).compact ? minTouchTarget : _menuWidth,
            child: actions.isEmpty
                ? null
                : PopupMenuButton<UserAction>(
                    useRootNavigator: true,
                    key: Key('user-menu-${user.id}'),
                    tooltip: l.adminUsersActionsFor(user.name),
                    // Il menu resta (spento) invece di sparire: il posto, e
                    // quindi l'altezza della riga, non cambiano; solo lo
                    // spinner prende quello dell'icona.
                    enabled: !_busy,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: _spinnerSize,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.ellipsisVertical,
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
    return user.enabled ? tile : Opacity(opacity: 0.55, child: tile);
  }
}

/// "Admin" (oro su oro) o "Disattivato" (crema su crema).
class _Badge extends StatelessWidget {
  const _Badge(
      {required this.text, required this.color, required this.background});

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 12)),
      );
}

/// La casellina di un canale: piena (crema 12%) se collegato, con il solo
/// bordo se no; il tooltip dice il contatto (l'email è mascherata dal
/// plugin).
class _ContactBox extends StatelessWidget {
  const _ContactBox(
      {required this.label, required this.linked, required this.tooltip});

  final String label;
  final bool linked;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Container(
          width: _contactBoxSize,
          height: _contactBoxSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: linked ? WfColors.cream.withValues(alpha: 0.12) : null,
            border: linked ? null : Border.all(color: WfColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: linked ? WfColors.cream : WfColors.creamMuted)),
        ),
      );
}
