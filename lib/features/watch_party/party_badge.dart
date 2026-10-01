import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_menus.dart';
import 'watch_party_session.dart';

/// Etichetta con bordo oro e icona del gruppo, nella barra in alto
/// (`watch_party_button.dart`). Nel player c'è [PartyBadge].
class PartyChip extends StatelessWidget {
  const PartyChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: WfColors.gold),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.users, size: 16, color: WfColors.gold),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: WfColors.gold, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// Iniziale di un membro: il server dà solo i nomi utente.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 13,
        backgroundColor: WfColors.surfaceHigh,
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
            style: const TextStyle(
                color: WfColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      );
}

/// Iniziali dei membri, sovrapposte (spec D §15.2): al massimo
/// [maxShown], poi "+N". Chi entra compare con un "pop"; chi esce lascia
/// stringere la fila (con le animazioni ridotte la larghezza cambia di
/// colpo).
class MemberAvatarStack extends StatelessWidget {
  const MemberAvatarStack({super.key, required this.members});

  final List<String> members;

  static const maxShown = 3;

  /// Di quanto un'iniziale copre la precedente.
  static const overlap = 8.0;

  /// Diametro di `MemberAvatar` (raggio 13).
  static const avatarSize = 26.0;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    final shown = members.take(maxShown).toList();
    final extra = members.length - shown.length;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++)
          Align(
            key: ValueKey(shown[i]),
            alignment: Alignment.centerRight,
            widthFactor: i == 0 ? 1 : (avatarSize - overlap) / avatarSize,
            // Alta quanto l'iniziale, anche se sopra c'è spazio in più.
            heightFactor: 1,
            child: _AvatarPop(child: MemberAvatar(name: shown[i])),
          ),
        if (extra > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('+$extra',
                style: const TextStyle(
                    color: WfColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
      ],
    );
    // Ridotto: niente movimento, solo dissolvenze (spec D §6.2), quindi la
    // larghezza cambia di colpo. Niente `AnimatedSize` con durata zero: il
    // suo assert scatterebbe.
    if (motion.isReduced) return row;
    return AnimatedSize(
      duration: WfMotion.medium,
      curve: WfMotion.emphasized,
      // Ancorata a sinistra: mentre la larghezza si adatta, le iniziali che
      // restano non si spostano.
      alignment: Alignment.centerLeft,
      child: row,
    );
  }
}

/// Un'iniziale nuova cresce con un piccolo rimbalzo (con le animazioni
/// ridotte sfuma soltanto).
class _AvatarPop extends StatelessWidget {
  const _AvatarPop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion.duration(WfMotion.medium),
      curve: motion.isReduced ? WfMotion.standard : WfMotion.bounce,
      builder: (context, t, child) => motion.isReduced
          ? Opacity(opacity: t.clamp(0.0, 1.0), child: child)
          : Transform.scale(scale: t, child: child),
      child: child,
    );
  }
}

/// "Watch party · N" nei controlli del player, con le iniziali dei membri:
/// apre i membri ed "Esci dal watch party". A ogni cambio di membri fa un
/// piccolo sobbalzo (spec D §15.2).
class PartyBadge extends ConsumerStatefulWidget {
  const PartyBadge({super.key, required this.onLeave});

  final VoidCallback onLeave;

  /// Scala massima del sobbalzo.
  static const bumpScale = 1.08;

  @override
  ConsumerState<PartyBadge> createState() => _PartyBadgeState();
}

class _PartyBadgeState extends ConsumerState<PartyBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bump =
      AnimationController(vsync: this, duration: WfMotion.medium);
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: PartyBadge.bumpScale)
            .chain(CurveTween(curve: WfMotion.decelerate)),
        weight: 40),
    TweenSequenceItem(
        tween: Tween(begin: PartyBadge.bumpScale, end: 1.0)
            .chain(CurveTween(curve: WfMotion.bounce)),
        weight: 60),
  ]).animate(_bump);

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final party = ref.watch(watchPartySessionProvider);
    final members = party.members;
    final reduced = WfMotion.of(context).isReduced;
    ref.listen(watchPartySessionProvider.select((s) => s.members.length),
        (_, _) {
      if (!reduced) unawaited(_bump.forward(from: 0));
    });
    return PopupMenuButton<String>(
      key: const Key('party-badge'),
      tooltip: party.group?.name,
      position: PopupMenuPosition.under,
      popUpAnimationStyle: wfPopUpAnimation(context),
      onSelected: (value) {
        if (value == 'leave') widget.onLeave();
      },
      itemBuilder: (context) => [
        for (final member in members)
          PopupMenuItem<String>(
            enabled: false,
            child: Row(
              children: [
                MemberAvatar(name: member),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(member,
                      style: const TextStyle(color: WfColors.cream)),
                ),
              ],
            ),
          ),
        if (members.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'leave',
          child: Row(
            children: [
              const Icon(LucideIcons.logOut, size: 18, color: WfColors.error),
              const SizedBox(width: 12),
              Flexible(child: Text(l.watchPartyLeave)),
            ],
          ),
        ),
      ],
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
          decoration: BoxDecoration(
            border: Border.all(color: WfColors.gold),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MemberAvatarStack(members: members),
              const SizedBox(width: 8),
              Text(l.watchPartyButton(members.length),
                  style: const TextStyle(
                      color: WfColors.gold, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
