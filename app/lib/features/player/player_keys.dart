import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';

/// Riquadro di un tasto, come il `kbd` della bozza del player.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: WfColors.surfaceHigh,
        border: const Border(
          top: BorderSide(color: WfColors.border),
          left: BorderSide(color: WfColors.border),
          right: BorderSide(color: WfColors.border),
          bottom: BorderSide(color: WfColors.border, width: 2),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: WfColors.cream,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

/// Suggerimento di un comando; col [shortcut] mostra anche il suo tasto.
/// Senza tasto (dito, TV) è un `Tooltip` normale.
class KeyTooltip extends StatelessWidget {
  const KeyTooltip({
    super.key,
    required this.message,
    this.shortcut,
    required this.child,
  });

  final String message;
  final String? shortcut;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final key = shortcut;
    if (key == null) return Tooltip(message: message, child: child);
    return RawTooltip(
      semanticsTooltip: message,
      ignorePointer: true,
      positionDelegate: (c) => positionDependentBox(
        size: c.overlaySize,
        childSize: c.tooltipSize,
        target: c.target,
        verticalOffset: 24,
        preferBelow: true,
      ),
      tooltipBuilder: (context, animation) => FadeTransition(
        opacity: animation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: WfColors.surface,
            border: Border.all(color: WfColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          // Nell'overlay non c'è un Material: lo stile del tema (Inter) va
          // messo a mano.
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: WfColors.cream,
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.none,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text(message), const SizedBox(width: 10), KeyCap(key)],
            ),
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Scheda "Tasti", come un programma di sala: doppio filo oro e i puntini
/// fino al tasto. Si vede solo dove i tasti esistono (`!tv && !touch`).
class PlayerKeysCard extends StatelessWidget {
  const PlayerKeysCard({super.key});

  static const width = 420.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget group(String title) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(title,
              style: const TextStyle(
                  color: WfColors.gold,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1)),
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: width),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WfColors.surface,
          border: Border.all(color: WfColors.gold),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
                color: WfColors.bg.withValues(alpha: 0.6),
                offset: const Offset(0, 30),
                blurRadius: 70),
          ],
        ),
        child: Stack(
          children: [
            // Il secondo filo, rientrato.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: WfColors.gold.withValues(alpha: 0.35)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 26, 30, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.playerKeysTitle,
                      textAlign: TextAlign.center,
                      style: WfText.display(40).copyWith(letterSpacing: 3)),
                  const Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 4),
                    child: _Ornament(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(l.playerKeysHint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: WfColors.creamMuted, fontSize: 12)),
                  ),
                  group(l.playerKeysPlayback),
                  _KeyRow(l.playerKeysPlayPause, [l.playerKeySpace]),
                  _KeyRow(l.playerKeysSeek, const ['←', '→']),
                  _KeyRow(l.playerVolume, const ['↑', '↓']),
                  _KeyRow(l.playerKeysMute, const ['M']),
                  _KeyRow(l.playerFullscreen, const ['F']),
                  group(l.playerKeysEpisodesSubtitles),
                  _KeyRow(l.playerKeysNextPrevious, const ['N', 'P']),
                  _KeyRow(l.playerKeysSubtitleDelay, const ['G', 'H']),
                  group(l.playerKeysTogether),
                  _KeyRow(l.playerKeysChat, [l.playerKeyEnter]),
                  _KeyRow(l.playerKeysReactions, const ['1–6']),
                  const SizedBox(height: 10),
                  _KeyRow(l.playerKeysClose, [l.playerKeyEsc]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Due fili oro e un rombo sotto il titolo.
class _Ornament extends StatelessWidget {
  const _Ornament();

  @override
  Widget build(BuildContext context) {
    final rule = Container(
        width: 70, height: 1, color: WfColors.gold.withValues(alpha: 0.5));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        rule,
        const SizedBox(width: 10),
        Transform.rotate(
          angle: 0.785398, // 45°
          child: const SizedBox.square(
              dimension: 5, child: ColoredBox(color: WfColors.gold)),
        ),
        const SizedBox(width: 10),
        rule,
      ],
    );
  }
}

/// "azione ……… tasti": i puntini corrono sotto tutta la riga e il testo e
/// i tasti li coprono col fondo della scheda (un'azione lunga va a capo).
class _KeyRow extends StatelessWidget {
  const _KeyRow(this.action, this.keys);

  final String action;
  final List<String> keys;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Stack(
          children: [
            const Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              child: CustomPaint(
                  painter: _DotsPainter(), size: Size.fromHeight(1)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: ColoredBox(
                    color: WfColors.surface,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(action,
                          style: const TextStyle(
                              color: WfColors.cream, fontSize: 13)),
                    ),
                  ),
                ),
                ColoredBox(
                  color: WfColors.surface,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (i, key) in keys.indexed) ...[
                          if (i > 0) const SizedBox(width: 4),
                          KeyCap(key),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

/// Bordo inferiore punteggiato, `cream` al 28%.
class _DotsPainter extends CustomPainter {
  const _DotsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = WfColors.cream.withValues(alpha: 0.28);
    for (var x = 0.0; x < size.width; x += 3) {
      canvas.drawRect(Rect.fromLTWH(x, size.height - 1, 1, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => false;
}
