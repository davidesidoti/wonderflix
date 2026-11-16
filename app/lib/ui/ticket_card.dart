import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/hero_launch.dart';
import '../app/motion.dart';
import '../app/navigation.dart';
import '../app/theme.dart';
import '../core/jellyfin/item_models.dart';
import '../features/home/home_sections.dart';
import '../features/library/item_labels.dart';
import '../features/library/library_providers.dart';
import '../features/library/user_data.dart';
import '../l10n/gen/app_localizations.dart';
import 'card_preview.dart';
import 'card_preview_host.dart';
import 'form_factor.dart';
import 'poster_card.dart';
import 'tv_focusable.dart';
import 'wf_image.dart';

/// Misure del biglietto: larghezza, altezza e larghezza dell'immagine.
typedef TicketSize = ({double width, double height, double image});

/// Desktop 392x124, finestra stretta 300x104, TV 330x108 (spec §6.2, §12, §13).
/// La TV è anche `compact`: si controlla per prima.
TicketSize ticketSize(BuildContext context) {
  final form = FormFactor.of(context);
  if (form.tv) return (width: 330, height: 108, image: 182);
  if (form.compact) return (width: 300, height: 104, image: 150);
  return (width: 392, height: 124, image: 220);
}

/// Il biglietto di "Stasera": immagine, strappo e matrice con i minuti che
/// restano ([resumed]) o "Prossimo" (da Prossimi episodi).
/// Clic, anteprima, volo Hero e focus TV come `LandscapeCard`.
class TicketCard extends ConsumerStatefulWidget {
  const TicketCard({
    super.key,
    required this.item,
    required this.resumed,
    this.heroSource,
    this.previewExtra,
    this.autofocus = false,
  });

  final JellyfinItem item;

  /// Titolo da riprendere (minuti che restano) e non l'episodio successivo.
  final bool resumed;

  /// Come `LandscapeCard.heroSource`.
  final String? heroSource;
  final CardPreviewExtra? previewExtra;
  final bool autofocus;

  @override
  ConsumerState<TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends ConsumerState<TicketCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final size = ticketSize(context);
    final narrow = FormFactor.of(context).compact;
    final progress = watchUserData(ref, item).progress;
    final subtitle = cardSubtitle(item);
    final source = widget.heroSource;
    final heroSource =
        source == null ? null : WfHeroScope.source(context, source);

    void activate() => openItem(context, item, heroSource: heroSource);

    final card = SizedBox(
      width: size.width,
      height: size.height,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = !FormFactor.of(context).touch),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: activate,
          child: TvFocusable(
            onActivate: activate,
            autofocus: widget.autofocus,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: WfMotion.fast,
              transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
              child: Stack(
                children: [
                  ClipPath(
                    clipper: _TicketClipper(size.image),
                    child: ColoredBox(
                      color: WfColors.surface,
                      child: Row(
                        children: [
                          SizedBox(
                            key: const Key('ticket-image'),
                            width: size.image,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                WfHero(
                                  tag: heroSource == null
                                      ? null
                                      : WfHeroTag(item.id, heroSource),
                                  child: WfImage(
                                      image: ref
                                          .watch(imageUrlsProvider)
                                          .landscape(item)),
                                ),
                                if (progress != null)
                                  ProgressStrip(progress: progress),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 14, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(cardTitle(item),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13.5)),
                                  if (subtitle != null)
                                    Text(subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: WfColors.creamMuted,
                                            fontSize: 12)),
                                  const Spacer(),
                                  _Stub(
                                      item: item,
                                      resumed: widget.resumed,
                                      narrow: narrow),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Bordo oro col mouse sopra; sulla TV lo disegna TvFocusable.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: WfMotion.fast,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color:
                                  _hover ? WfColors.gold : Colors.transparent,
                              width: 2),
                        ),
                      ),
                    ),
                  ),
                  // La linea dello strappo; i mezzi cerchi sono ritagliati.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                          key: const Key('ticket-tear'),
                          painter: _TearPainter(size.image)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return CardPreviewHost(
        item: item,
        heroSource: heroSource,
        extra: widget.previewExtra,
        child: card);
  }
}

/// In basso nella matrice: "52 min restano" oppure "Prossimo 58 min".
class _Stub extends StatelessWidget {
  const _Stub({required this.item, required this.resumed, required this.narrow});

  final JellyfinItem item;
  final bool resumed;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const small =
        TextStyle(color: WfColors.creamMuted, fontSize: 11, fontWeight: FontWeight.w500);
    final String big;
    final Color color;
    final double fontSize;
    final String? label;
    if (resumed) {
      final minutes = remainingMinutes(item);
      if (minutes == null) return const SizedBox.shrink();
      big = l.ticketMinutes(minutes);
      color = WfColors.cream;
      fontSize = narrow ? 24 : 30;
      label = l.ticketLeft;
    } else {
      final ticks = item.runTimeTicks;
      final minutes = ticks == null ? 0 : (ticks / 600000000).round();
      big = l.ticketNext;
      color = WfColors.gold;
      fontSize = 22;
      label = minutes > 0 ? l.ticketMinutes(minutes) : null;
    }
    // Se la matrice è stretta (o il testo grande) tutto rimpicciolisce.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(big, style: WfText.display(fontSize, color: color)),
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(left: 5),
              child: Text(label, maxLines: 1, style: small),
            ),
        ],
      ),
    );
  }
}

/// La sagoma del biglietto: rettangolo arrotondato con i due mezzi cerchi
/// dello strappo (in alto e in basso, alla larghezza [x]) tagliati via, così
/// si vede il fondo qualunque sia.
class _TicketClipper extends CustomClipper<Path> {
  const _TicketClipper(this.x);

  final double x;

  @override
  Path getClip(Size size) => Path.combine(
        PathOperation.difference,
        Path()
          ..addRRect(RRect.fromRectAndRadius(
              Offset.zero & size, const Radius.circular(8))),
        Path()
          ..addOval(Rect.fromCircle(center: Offset(x, 0), radius: 7))
          ..addOval(Rect.fromCircle(center: Offset(x, size.height), radius: 7)),
      );

  @override
  bool shouldReclip(_TicketClipper old) => old.x != x;
}

/// La linea tratteggiata verticale dello strappo, alla larghezza [x] (quella
/// dell'immagine), tra i due mezzi cerchi.
class _TearPainter extends CustomPainter {
  const _TearPainter(this.x);

  final double x;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFF333333)
      ..strokeWidth = 1;
    for (var y = 9.0; y + 4 < size.height - 7; y += 7) {
      canvas.drawLine(Offset(x + 0.5, y), Offset(x + 0.5, y + 4), line);
    }
  }

  @override
  bool shouldRepaint(_TearPainter old) => old.x != x;
}
