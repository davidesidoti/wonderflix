import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_buttons.dart';

/// Quanto resta una carta d'invito prima di chiudersi da sola.
const inviteCardShowFor = Duration(seconds: 10);

/// I tre tipi di carta d'invito.
enum InviteKind { party, match, friend }

/// La carta mostrata per ultima: solo lei ha il pulsante oro.
class NewestInvite extends Notifier<InviteKind?> {
  @override
  InviteKind? build() => null;

  void set(InviteKind kind) => state = kind;
}

final newestInviteProvider =
    NotifierProvider<NewestInvite, InviteKind?>(NewestInvite.new);

/// Il posto della carta d'invito in alto a destra (spec C §11.4): entra da
/// destra e se ne va in dissolvenza; quella che esce non riceve più clic.
/// [card] `null` = nessun invito; [id] distingue un invito dall'altro.
class InviteCardSlot extends StatelessWidget {
  const InviteCardSlot({super.key, required this.id, required this.card});

  final Object? id;
  final Widget? card;

  @override
  Widget build(BuildContext context) {
    final current = card == null
        ? const SizedBox.shrink(key: ValueKey('no-invite'))
        : KeyedSubtree(key: ValueKey(id), child: card!);
    return AnimatedSwitcher(
      duration: WfMotion.of(context).duration(WfMotion.medium),
      transitionBuilder: (child, animation) => IgnorePointer(
        // L'invito che se ne va non accetta più "Unisciti".
        ignoring: child.key != current.key,
        child: FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.3, 0), end: Offset.zero)
                .animate(CurvedAnimation(
                    parent: animation, curve: WfMotion.emphasized)),
            child: child,
          ),
        ),
      ),
      child: current,
    );
  }
}

/// La carta d'invito (party, match e amicizia, spec §7.4): avatar, frase,
/// dettaglio e due azioni; in fondo la barretta dei [inviteCardShowFor], che
/// a fine corsa chiama [onTimeout]. Col puntatore sopra o il fuoco dentro si
/// ferma e poi riparte da dove era; con il movimento ridotto non c'è e la
/// carta non si chiude da sola.
class InviteCardFrame extends StatefulWidget {
  const InviteCardFrame({
    super.key,
    required this.leading,
    required this.sentence,
    this.detail,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.secondaryIcon,
    required this.onSecondary,
    required this.newest,
    required this.onTimeout,
  });

  final Widget leading;
  final InlineSpan sentence;
  final String? detail;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final IconData secondaryIcon;
  final VoidCallback onSecondary;

  /// La carta più recente: l'azione principale è oro.
  final bool newest;
  final VoidCallback onTimeout;

  @override
  State<InviteCardFrame> createState() => _InviteCardFrameState();
}

class _InviteCardFrameState extends State<InviteCardFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdown =
      AnimationController(vsync: this, duration: inviteCardShowFor)
        ..addListener(() {
          // Il valore arriva a 1 un frame prima dello stato `completed`.
          if (_countdown.value < 1 || _timedOut) return;
          _timedOut = true;
          widget.onTimeout();
        });
  bool _timedOut = false;
  bool _reduced = true;
  bool _hovered = false;
  bool _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = WfMotion.of(context).isReduced;
    _sync();
  }

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

  /// Corre solo senza movimento ridotto, puntatore e fuoco; `forward`
  /// riparte dal valore di adesso, cioè dal tempo che mancava.
  void _sync() {
    if (_reduced || _hovered || _focused) {
      _countdown.stop();
    } else if (!_countdown.isAnimating && !_countdown.isCompleted) {
      _countdown.forward();
    }
  }

  void _set(VoidCallback change) {
    change();
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final primary = widget.newest
        ? WfButton.primary(
            label: widget.primaryLabel,
            icon: widget.primaryIcon,
            onPressed: widget.onPrimary)
        : WfButton.secondary(
            label: widget.primaryLabel,
            icon: widget.primaryIcon,
            onPressed: widget.onPrimary);
    return MouseRegion(
      onEnter: (_) => _set(() => _hovered = true),
      onExit: (_) => _set(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => _set(() => _focused = focused),
        child: Material(
          color: WfColors.surface,
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            // Nel layout stretto a tutta larghezza (spec 1c §4.2).
            width: FormFactor.of(context).compact ? double.infinity : 340,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      widget.leading,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              widget.sentence,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            if (detail != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  detail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: WfColors.creamMuted,
                                    fontSize: 12.5,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            // Wrap e non Row: con testi lunghi o ingranditi
                            // i due pulsanti vanno a capo.
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                primary,
                                WfButton.secondary(
                                  label: widget.secondaryLabel,
                                  icon: widget.secondaryIcon,
                                  onPressed: widget.onSecondary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_reduced)
                  AnimatedBuilder(
                    animation: _countdown,
                    builder: (context, _) => Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        key: const Key('invite-countdown'),
                        widthFactor: 1 - _countdown.value,
                        child: const SizedBox(
                          height: 3,
                          child: ColoredBox(color: WfColors.gold),
                        ),
                      ),
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
