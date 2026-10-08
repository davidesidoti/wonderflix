import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/user_avatar.dart';
import 'party_channel.dart';

/// Ripiego per le emoji scritte nella chat: quelle a colori di Windows
/// (spec E §9.1).
const partyEmojiFontFallback = ['Segoe UI Emoji'];

/// Diametro dell'avatar accanto al nome nella chat.
const partyChatAvatarSize = 18.0;

/// Testo della chat: crema, con le emoji di Windows come ripiego. Il font
/// resta quello dell'app (si eredita).
const partyChatTextStyle = TextStyle(
  color: WfColors.cream,
  fontSize: 14,
  height: 1.35,
  fontFamilyFallback: partyEmojiFontFallback,
);

/// Una riga della chat: l'avatar del mittente (spec K §10.5), il nome in oro
/// e il testo (spec E §9.1). I nostri messaggi non ancora confermati sono più
/// trasparenti (§9.4).
class PartyChatMessage extends StatefulWidget {
  const PartyChatMessage({super.key, required this.entry, this.maxLines});

  /// Opacità di un nostro messaggio non ancora confermato.
  static const pendingOpacity = 0.6;

  final PartyChatEntry entry;

  /// `null` = tutte le righe (storico).
  final int? maxLines;

  @override
  State<PartyChatMessage> createState() => _PartyChatMessageState();
}

class _PartyChatMessageState extends State<PartyChatMessage> {
  /// L'avatar, sempre lo stesso widget finché il mittente non cambia: un
  /// `WidgetSpan` confronta il figlio per identità, e un widget nuovo a ogni
  /// build rifarebbe il layout del paragrafo (per esempio a ogni tasto nel
  /// campo della chat). Niente misure "a secco" qui intorno (vedi
  /// [UserAvatar]).
  late Widget _avatar = _buildAvatar();

  Widget _buildAvatar() {
    final event = widget.entry.event;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: UserAvatar.lookup(
        userId: event.userId,
        name: event.userName,
        size: partyChatAvatarSize,
        muted: true,
      ),
    );
  }

  @override
  void didUpdateWidget(PartyChatMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.entry.event;
    final event = widget.entry.event;
    if (before.userId != event.userId || before.userName != event.userName) {
      _avatar = _buildAvatar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = widget.entry;
    final maxLines = widget.maxLines;
    final name = entry.mine ? l.partyChatYou : entry.event.userName;
    return Opacity(
      opacity: entry.pending ? PartyChatMessage.pendingOpacity : 1,
      child: Text.rich(
        TextSpan(children: [
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: _avatar),
          TextSpan(
              text: name,
              style: const TextStyle(
                  color: WfColors.gold, fontWeight: FontWeight.w600)),
          const TextSpan(text: '  '),
          TextSpan(text: entry.event.text),
        ]),
        style: partyChatTextStyle,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      ),
    );
  }
}

/// Bolla della chat chiusa: un messaggio su fondo scuro, al massimo
/// [maxLines] righe (spec E §9.2).
class PartyChatBubble extends StatelessWidget {
  const PartyChatBubble({super.key, required this.entry});

  /// Larghezza massima di bolle, storico e campo.
  static const width = 360.0;
  static const maxLines = 4;
  static const radius = 10.0;

  /// Opacità del fondo.
  static const backgroundAlpha = 0.72;

  /// Spazio sopra ogni bolla.
  static const gap = 6.0;

  final PartyChatEntry entry;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: width),
        margin: const EdgeInsets.only(top: gap),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: WfColors.bg.withValues(alpha: backgroundAlpha),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: PartyChatMessage(entry: entry, maxLines: maxLines),
      );
}

/// Una bolla che entra (dissolvenza e [rise] px verso l'alto; con le
/// animazioni ridotte solo dissolvenza) ed esce sfumando quando [leaving]
/// diventa `true`; finita l'uscita chiama [onGone].
class AnimatedChatBubble extends StatelessWidget {
  const AnimatedChatBubble({
    super.key,
    required this.entry,
    required this.leaving,
    required this.onGone,
  });

  /// Di quanto sale entrando.
  static const rise = 8.0;

  final PartyChatEntry entry;
  final bool leaving;
  final VoidCallback onGone;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    return AnimatedOpacity(
      opacity: leaving ? 0 : 1,
      duration: WfMotion.fast,
      curve: WfMotion.accelerate,
      onEnd: leaving ? onGone : null,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: motion.duration(WfMotion.medium),
        curve: WfMotion.emphasized,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, motion.isReduced ? 0 : (1 - t) * rise),
            child: child,
          ),
        ),
        child: PartyChatBubble(entry: entry),
      ),
    );
  }
}
