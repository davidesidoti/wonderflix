import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/motion.dart';
import '../app/theme.dart';
import 'form_factor.dart';
import 'tv_focusable.dart';
import 'smooth_scroll.dart';
import 'staggered_entrance.dart';

/// Card di una riga che entrano volando (le prime visibili).
const rowEntranceCount = 8;

/// Aria sopra e sotto le card di una riga sulla TV, per il focus ingrandito.
const tvRowFocusPadding = 12.0;

/// Passo tra una card e l'altra nell'entrata di una riga.
const rowEntranceStagger = Duration(milliseconds: 40);

/// Misure delle card di una riga: locandine 160 e card 16:9 da 300, più
/// piccole nel layout stretto, con l'altezza della riga che le contiene.
typedef RowCardSize = ({double width, double rowHeight});

RowCardSize rowPosterSize(BuildContext context) =>
    FormFactor.of(context).compact
    ? (width: 112, rowHeight: 230)
    : (width: 160, rowHeight: 300);

RowCardSize rowLandscapeSize(BuildContext context) =>
    FormFactor.of(context).compact
    ? (width: 220, rowHeight: 190)
    : (width: 300, rowHeight: 230);

/// Riga orizzontale con titolo e frecce (per chi usa il mouse).
class MediaRow extends StatefulWidget {
  const MediaRow({
    super.key,
    required this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.animateEntrance = false,
    this.onTitleTap,
    this.trailing,
  });

  final String title;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Le prime card visibili entrano "volando" da destra insieme alla riga
  /// (spec C §8.2): solo se la riga è uno [StaggerItem] che sta entrando
  /// (vedi [StaggerGroup.nested]). Una riga già entrata, ricostruita più
  /// tardi, non le rifà volare.
  final bool animateEntrance;

  /// Con [onTitleTap] il titolo è un link, con una freccia (spec K §8.3).
  final VoidCallback? onTitleTap;

  /// A destra nell'intestazione, prima delle frecce.
  final Widget? trailing;

  @override
  State<MediaRow> createState() => _MediaRowState();
}

class _MediaRowState extends State<MediaRow> {
  final _controller = SmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scroll(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target =
        (position.pixels + direction * position.viewportDimension * 0.8).clamp(
          0.0,
          position.maxScrollExtent,
        );
    _controller.animateTo(
      target,
      duration: WfMotion.medium,
      curve: WfMotion.decelerate,
    );
  }

  Widget _title() {
    final title = Text(
      widget.title,
      overflow: TextOverflow.ellipsis,
      style: WfText.display(24),
    );
    final onTap = widget.onTitleTap;
    if (onTap == null) return title;
    // Sulla TV il link si raggiunge col telecomando.
    return TvFocusable(
      onActivate: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const Key('row-title-link'),
          // Anche lo spazio tra il titolo e la freccia è parte del link.
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: title),
              const SizedBox(width: 8),
              const Icon(
                LucideIcons.arrowRight,
                size: 20,
                color: WfColors.gold,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final animate = widget.animateEntrance;
    final form = FormFactor.of(context);
    final side = form.compact ? 16.0 : 32.0;
    Widget list = ListView.separated(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      // Sulla TV un po' d'aria sopra e sotto: l'ingrandimento del focus non
      // viene tagliato dalla lista.
      padding: EdgeInsets.symmetric(
        horizontal: side,
        vertical: form.tv ? tvRowFocusPadding : 0,
      ),
      itemCount: widget.itemCount,
      separatorBuilder: (context, index) => const SizedBox(width: 16),
      // Senza entrata le card non si avvolgono: uno StaggerItem cercherebbe
      // il gruppo più vicino, che potrebbe essere quello della pagina.
      itemBuilder: !animate
          ? widget.itemBuilder
          : (context, i) => StaggerItem(
              index: i,
              effect: EntranceEffect.fly,
              child: widget.itemBuilder(context, i),
            ),
    );
    if (animate) {
      list = StaggerGroup(
        count: rowEntranceCount,
        stagger: rowEntranceStagger,
        nested: true,
        child: list,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: Row(
              children: [
                Flexible(child: _title()),
                const Spacer(),
                ?widget.trailing,
                if (!form.tv) ...[
                  IconButton(
                    key: const Key('row-previous'),
                    onPressed: () => _scroll(-1),
                    icon: const Icon(
                      LucideIcons.chevronLeft,
                      color: WfColors.cream,
                    ),
                  ),
                  IconButton(
                    key: const Key('row-next'),
                    onPressed: () => _scroll(1),
                    icon: const Icon(
                      LucideIcons.chevronRight,
                      color: WfColors.cream,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: widget.height + (form.tv ? 2 * tvRowFocusPadding : 0),
            child: list,
          ),
        ],
      ),
    );
  }
}
