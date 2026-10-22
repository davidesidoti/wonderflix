import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/storage/profile_store.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_confirm_dialog.dart';
import '../auth/profiles_state.dart';
import '../auth/session_controller.dart';
import 'avatar_dialog.dart';

/// Diametro dell'avatar di un profilo in "Chi guarda?" (spec K §9.4).
const profileAvatarSize = 120.0;

/// Larghezza di una card di "Chi guarda?".
const _cardWidth = 150.0;

/// Opacità dell'avatar di un profilo scaduto.
const _expiredOpacity = 0.45;

/// Opacità del velo scuro sull'avatar del profilo che si apre: sull'oro lo
/// spinner non si vedrebbe.
const _openingScrimAlpha = 0.55;

// Misure verticali: con queste "Chi guarda?" sta tutta nella finestra più
// piccola (1024×640, circa 600 px utili) senza scorrere, anche con un
// profilo scaduto ("Accedi di nuovo" sotto il nome).

/// Lato del logo (è quadrato).
const _logoSize = 140.0;

/// Margine intorno al contenuto.
const _padding = 24.0;

/// Distanza tra il logo e il titolo, e tra le card e "Gestisci profili".
const _gap = 24.0;

/// Distanza tra il titolo e le card.
const _titleGap = 28.0;

/// Il nome da mostrare: un profilo migrato il cui primo `/Users/Me` non è
/// riuscito non ha ancora un nome.
String _displayName(AppLocalizations l, StoredProfile profile) =>
    profile.name.isEmpty ? l.profilesUnnamed : profile.name;

/// "Chi guarda?" (spec K §9.4): i profili del PC, "Aggiungi profilo" e
/// "Gestisci profili". La lingua è quella dell'ultimo profilo usato.
class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key});

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  bool _managing = false;

  /// Il profilo che si sta aprendo: intanto gli altri clic non fanno niente.
  /// Le card restano attive (il fuoco resta dov'è): è [_open] a ignorarli.
  String? _opening;

  SessionController get _session =>
      ref.read(sessionControllerProvider.notifier);

  Future<void> _open(StoredProfile profile) async {
    if (_opening != null || _managing) return;
    if (profile.expired) {
      _session.relogin(profile.userId);
      return;
    }
    setState(() => _opening = profile.userId);
    try {
      await _session.openProfile(profile.userId);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _remove(StoredProfile profile) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showWfConfirmDialog(
      context,
      title: l.profilesRemoveTitle(_displayName(l, profile)),
      message: l.profilesRemoveBody,
      confirmLabel: l.profilesRemove,
      cancelLabel: l.profilesCancel,
    );
    if (!confirmed || !mounted) return;
    await _session.removeProfile(profile.userId);
  }

  void _setManaging(bool managing) => setState(() => _managing = managing);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final book = ref.watch(profilesProvider.select((p) => p.book));
    final idle = _opening == null;
    // Il fuoco parte dall'ultimo profilo usato, altrimenti dal primo: Invio
    // lo apre subito.
    final last = book.lastUserId;
    final focusUserId = (last == null ? null : book.byId(last)?.userId) ??
        book.profiles.firstOrNull?.userId;
    // Esc in "Gestisci profili" fa come "Fine". Un tasto, non `DismissIntent`:
    // le `Actions` dello `Scaffold` lo fermerebbero con il fuoco su "Fine" o
    // su Rimuovi.
    return CallbackShortcuts(
      bindings: {
        if (_managing)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _setManaging(false),
      },
      // Il fuoco resta nella schermata: la card che lo aveva si spegne in
      // "Gestisci profili", ed Esc deve arrivare lo stesso.
      child: FocusScope(
        child: Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(_padding),
              // Il logo, il titolo, le card e "Gestisci profili", uno dopo
              // l'altro come nel login (spec C §11.3).
              child: StaggerGroup(
                count: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StaggerItem(
                      index: 0,
                      // Con l'altezza fissa niente scatto quando l'immagine
                      // arriva.
                      child: Image.asset('assets/brand/logo.png',
                          width: _logoSize, height: _logoSize),
                    ),
                    const SizedBox(height: _gap),
                    StaggerItem(
                      index: 1,
                      child: Text(l.profilesTitle, style: WfText.display(48)),
                    ),
                    const SizedBox(height: _titleGap),
                    StaggerItem(
                      index: 2,
                      child: Wrap(
                        spacing: 24,
                        runSpacing: 24,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final profile in book.profiles)
                            _ProfileCard(
                              key: ValueKey('profile-${profile.userId}'),
                              profile: profile,
                              managing: _managing,
                              opening: _opening == profile.userId,
                              autofocus: !_managing &&
                                  profile.userId == focusUserId,
                              onOpen: _managing
                                  ? null
                                  : () => unawaited(_open(profile)),
                              onRemove: () => unawaited(_remove(profile)),
                            ),
                          if (!book.isFull && !_managing)
                            _AddProfileCard(
                                key: const ValueKey('profile-add'),
                                onTap: idle ? _session.addProfile : null),
                        ],
                      ),
                    ),
                    if (!book.isEmpty) ...[
                      const SizedBox(height: _gap),
                      StaggerItem(
                        index: 3,
                        child: WfButton.secondary(
                          label: _managing ? l.profilesDone : l.profilesManage,
                          icon:
                              _managing ? LucideIcons.check : LucideIcons.pencil,
                          onPressed:
                              idle ? () => _setManaging(!_managing) : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un profilo: avatar e nome. Si apre con il clic o con Invio.
/// Per lo screen reader è un pulsante con il nome.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    super.key,
    required this.profile,
    required this.managing,
    required this.opening,
    required this.autofocus,
    required this.onOpen,
    required this.onRemove,
  });

  final StoredProfile profile;
  final bool managing;
  final bool opening;
  final bool autofocus;
  final VoidCallback? onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = _displayName(l, profile);
    return Semantics(
      container: true,
      // In "Gestisci profili" la card non si apre.
      button: !managing,
      label: name,
      hint: profile.expired ? l.profilesSignInAgain : null,
      child: SizedBox(
        width: _cardWidth,
        child: InkWell(
          onTap: onOpen,
          autofocus: autofocus,
          borderRadius: BorderRadius.circular(12),
          focusColor: WfColors.gold.withValues(alpha: 0.18),
          hoverColor: WfColors.gold.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Il nome lo dice già la card.
                    ExcludeSemantics(
                      child: Opacity(
                        opacity: profile.expired ? _expiredOpacity : 1,
                        child: UserAvatar(
                          userId: profile.userId,
                          name: profile.name,
                          size: profileAvatarSize,
                          imageTag: profile.imageTag,
                        ),
                      ),
                    ),
                    if (opening) ...[
                      Container(
                        key: ValueKey('profile-opening-${profile.userId}'),
                        width: profileAvatarSize,
                        height: profileAvatarSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: WfColors.bg.withValues(alpha: _openingScrimAlpha),
                        ),
                      ),
                      const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: WfColors.cream),
                      ),
                    ],
                    if (managing)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: IconButton(
                          key: ValueKey('profile-image-${profile.userId}'),
                          tooltip: l.profilesEditImage,
                          style: IconButton.styleFrom(
                              backgroundColor: WfColors.surfaceHigh),
                          // Un profilo scaduto non ha un token valido.
                          onPressed: profile.expired
                              ? null
                              : () => unawaited(showAvatarDialog(context,
                                  userId: profile.userId,
                                  name: name,
                                  imageTag: profile.imageTag)),
                          icon: const Icon(LucideIcons.pencil,
                              color: WfColors.cream),
                        ),
                      ),
                    if (managing)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          key: ValueKey('profile-remove-${profile.userId}'),
                          tooltip: l.profilesRemoveNamed(name),
                          style: IconButton.styleFrom(
                              backgroundColor: WfColors.surfaceHigh),
                          onPressed: onRemove,
                          icon: const Icon(LucideIcons.trash2,
                              color: WfColors.cream),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      if (profile.expired)
                        Text(l.profilesSignInAgain,
                            style: const TextStyle(
                                color: WfColors.gold, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Aggiungi profilo": un cerchio con il più.
class _AddProfileCard extends StatelessWidget {
  const _AddProfileCard({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).profilesAdd;
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: SizedBox(
        width: _cardWidth,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          focusColor: WfColors.gold.withValues(alpha: 0.18),
          hoverColor: WfColors.gold.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: profileAvatarSize,
                    height: profileAvatarSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: WfColors.border, width: 2),
                    ),
                    child: const Icon(LucideIcons.plus,
                        size: 40, color: WfColors.creamMuted),
                  ),
                  const SizedBox(height: 12),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: WfColors.creamMuted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
