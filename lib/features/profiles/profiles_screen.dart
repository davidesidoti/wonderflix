import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/storage/profile_store.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_confirm_dialog.dart';
import '../auth/profiles_state.dart';
import '../auth/session_controller.dart';

/// Diametro dell'avatar di un profilo in "Chi guarda?" (spec K §9.4).
const profileAvatarSize = 120.0;

/// Larghezza di una card di "Chi guarda?".
const _cardWidth = 150.0;

/// Opacità dell'avatar di un profilo scaduto.
const _expiredOpacity = 0.45;

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
  String? _opening;

  SessionController get _session =>
      ref.read(sessionControllerProvider.notifier);

  Future<void> _open(StoredProfile profile) async {
    if (_opening != null) return;
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
      title: l.profilesRemoveTitle(profile.name),
      message: l.profilesRemoveBody,
      confirmLabel: l.profilesRemove,
      cancelLabel: l.profilesCancel,
    );
    if (!confirmed || !mounted) return;
    await _session.removeProfile(profile.userId);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final book = ref.watch(profilesProvider.select((p) => p.book));
    final idle = _opening == null;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/brand/logo.png', width: 200),
              const SizedBox(height: 32),
              Text(l.profilesTitle, style: WfText.display(48)),
              const SizedBox(height: 32),
              Wrap(
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
                      onOpen: idle && !_managing
                          ? () => unawaited(_open(profile))
                          : null,
                      onRemove: () => unawaited(_remove(profile)),
                    ),
                  if (!book.isFull && !_managing)
                    _AddProfileCard(onTap: idle ? _session.addProfile : null),
                ],
              ),
              const SizedBox(height: 32),
              if (!book.isEmpty)
                WfButton.secondary(
                  label: _managing ? l.profilesDone : l.profilesManage,
                  icon: _managing ? LucideIcons.check : LucideIcons.pencil,
                  onPressed: idle
                      ? () => setState(() => _managing = !_managing)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un profilo: avatar (iniziale) e nome. Si apre con il clic o con Invio.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    super.key,
    required this.profile,
    required this.managing,
    required this.opening,
    required this.onOpen,
    required this.onRemove,
  });

  final StoredProfile profile;
  final bool managing;
  final bool opening;
  final VoidCallback? onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      width: _cardWidth,
      child: InkWell(
        onTap: onOpen,
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
                  Opacity(
                    opacity: profile.expired ? _expiredOpacity : 1,
                    child: _InitialAvatar(name: profile.name),
                  ),
                  if (opening)
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  if (managing)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        key: ValueKey('profile-remove-${profile.userId}'),
                        tooltip: l.profilesRemove,
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
              Text(profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              if (profile.expired)
                Text(l.profilesSignInAgain,
                    style:
                        const TextStyle(color: WfColors.gold, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// L'iniziale del nome su un cerchio dorato (il piano 17c la sostituisce con
/// l'immagine dell'utente).
class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: profileAvatarSize / 2,
        backgroundColor: WfColors.gold,
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
            style: const TextStyle(
                color: WfColors.bg,
                fontSize: profileAvatarSize * 0.4,
                fontWeight: FontWeight.w700)),
      );
}

/// "Aggiungi profilo": un cerchio con il più.
class _AddProfileCard extends StatelessWidget {
  const _AddProfileCard({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _cardWidth,
      child: InkWell(
        key: const ValueKey('profile-add'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        focusColor: WfColors.gold.withValues(alpha: 0.18),
        hoverColor: WfColors.gold.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(8),
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
              Text(AppLocalizations.of(context).profilesAdd,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: WfColors.creamMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
