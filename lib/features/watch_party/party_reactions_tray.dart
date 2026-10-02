import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/party_channel/party_channel_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'party_chat_bubble.dart';

/// Etichetta di una reazione (tooltip della barretta e testo accessibile).
String partyReactionLabel(AppLocalizations l, PartyReaction reaction) =>
    switch (reaction) {
      PartyReaction.joy => l.partyReactionJoy,
      PartyReaction.scream => l.partyReactionScream,
      PartyReaction.cry => l.partyReactionCry,
      PartyReaction.wow => l.partyReactionWow,
      PartyReaction.clap => l.partyReactionClap,
      PartyReaction.facepalm => l.partyReactionFacepalm,
    };

/// La barretta delle reazioni (spec E §10.2): le sei emoji con il loro
/// tasto. Un clic manda la reazione e la barretta resta aperta; senza il
/// mouse sopra si chiude da sola dopo [idleClose]. Sempre montata: chiusa è
/// invisibile e non prende i clic, così entra ed esce sfumando.
class PartyReactionsTray extends StatefulWidget {
  const PartyReactionsTray({
    super.key,
    required this.open,
    required this.onReaction,
    required this.onClose,
  });

  final bool open;
  final ValueChanged<PartyReaction> onReaction;
  final VoidCallback onClose;

  /// Senza il mouse sopra per questo tempo si chiude.
  static const idleClose = Duration(seconds: 5);

  /// Distanza dal pulsante.
  static const gap = 8.0;

  /// Dimensione delle emoji.
  static const emojiSize = 24.0;

  /// Opacità del fondo.
  static const backgroundAlpha = 0.94;

  /// Fondo crema al passaggio del mouse.
  static const hoverAlpha = 0.12;

  /// Scala di partenza dell'entrata.
  static const enterScale = 0.9;

  @override
  State<PartyReactionsTray> createState() => _PartyReactionsTrayState();
}

class _PartyReactionsTrayState extends State<PartyReactionsTray> {
  Timer? _idle;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.open) _restartIdle();
  }

  @override
  void didUpdateWidget(PartyReactionsTray oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) _restartIdle();
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  /// Riparte il conto dei [PartyReactionsTray.idleClose]; da chiusa o con il
  /// mouse sopra il timer non c'è.
  void _restartIdle() {
    _idle?.cancel();
    _idle = null;
    if (!widget.open || _hovered) return;
    _idle = Timer(PartyReactionsTray.idleClose, () {
      if (mounted && widget.open && !_hovered) widget.onClose();
    });
  }

  void _setHovered(bool hovered) {
    _hovered = hovered;
    _restartIdle();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    final open = widget.open;
    final duration = open ? motion.duration(WfMotion.medium) : WfMotion.fast;
    final curve = open ? WfMotion.emphasized : WfMotion.accelerate;
    return IgnorePointer(
      ignoring: !open,
      child: AnimatedOpacity(
        opacity: open ? 1 : 0,
        duration: duration,
        curve: curve,
        child: AnimatedScale(
          scale: open || motion.isReduced ? 1 : PartyReactionsTray.enterScale,
          alignment: Alignment.bottomRight,
          duration: duration,
          curve: curve,
          child: MouseRegion(
            onEnter: (_) => _setHovered(true),
            onExit: (_) => _setHovered(false),
            child: Material(
              color: WfColors.surface
                  .withValues(alpha: PartyReactionsTray.backgroundAlpha),
              shape: const StadiumBorder(
                  side: BorderSide(color: WfColors.border)),
              elevation: 6,
              shadowColor: Colors.black,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final reaction in PartyReaction.values)
                      Tooltip(
                        message: partyReactionLabel(l, reaction),
                        child: InkWell(
                          key: ValueKey('party-reaction-${reaction.id}'),
                          borderRadius:
                              BorderRadius.circular(PartyChatBubble.radius),
                          hoverColor: WfColors.cream
                              .withValues(alpha: PartyReactionsTray.hoverAlpha),
                          onTap: () {
                            widget.onReaction(reaction);
                            _restartIdle();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 3),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  reaction.emoji,
                                  style: const TextStyle(
                                    fontSize: PartyReactionsTray.emojiSize,
                                    height: 1.1,
                                    fontFamilyFallback:
                                        partyEmojiFontFallback,
                                  ),
                                ),
                                Text('${reaction.key}',
                                    style: const TextStyle(
                                        color: WfColors.creamMuted,
                                        fontSize: 9)),
                              ],
                            ),
                          ),
                        ),
                      ),
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
