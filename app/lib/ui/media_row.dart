import 'dart:math' as math;

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

  /// Sulla TV il nodo di ogni card costruita, per posizione.
  final _tvSlots = <int, FocusNode>{};

  /// La card col focus è sparita (la riga si è ricaricata): il focus va a
  /// quella che ora sta nello stesso posto, o all'ultima se la riga si è
  /// accorciata, invece di finire altrove nella pagina.
  void _refocus(int index) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusSlot(index));

  void _focusSlot(int index) {
    if (!mounted || widget.itemCount == 0) return;
    final slot = _tvSlots[math.min(index, widget.itemCount - 1)];
    slot?.traversalDescendants.firstOrNull?.requestFocus();
  }

  /// Sulla TV, lo scope della pagina: quando il focus ci torna si controlla
  /// la card lasciata.
  FocusScopeNode? _scope;

  /// La card che aveva il focus quando è uscito dalla pagina (un'altra
  /// pagina aperta sopra, la barra laterale), il suo posto e se intanto è
  /// sparita (la riga si è riletta).
  FocusNode? _leftNode;
  int _leftIndex = 0;
  bool _leftGone = false;

  void _slotBlurred(int index, FocusNode node) {
    if (_scope?.hasFocus ?? true) return;
    _leftNode = node;
    _leftIndex = index;
    _leftGone = false;
  }

  void _slotGone(int index, FocusNode node, {required bool focused}) {
    if (focused) _refocus(index);
    if (node == _leftNode) _leftGone = true;
  }

  /// Il focus torna sulla pagina: Flutter lo rimette sull'ultimo nodo
  /// rimasto (spesso "Riproduci" del carosello). Se la card lasciata è
  /// sparita, va invece a quella che ora sta nello stesso posto.
  void _onScopeFocus() {
    if (!(_scope?.hasFocus ?? false) || _leftNode == null) return;
    if (_leftGone) _focusSlot(_leftIndex);
    _leftNode = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = FormFactor.of(context).tv ? FocusScope.of(context) : null;
    if (scope == _scope) return;
    _scope?.removeListener(_onScopeFocus);
    _scope = scope?..addListener(_onScopeFocus);
  }

  @override
  void dispose() {
    _scope?.removeListener(_onScopeFocus);
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
      itemBuilder: (context, i) {
        final card = widget.itemBuilder(context, i);
        // Senza entrata le card non si avvolgono: uno StaggerItem cercherebbe
        // il gruppo più vicino, che potrebbe essere quello della pagina.
        final child = !animate
            ? card
            : StaggerItem(index: i, effect: EntranceEffect.fly, child: card);
        if (!form.tv) return child;
        // Chiave dalla card (mai la stessa, se globale): una card nuova al
        // suo posto ricrea lo slot, che così sa di aver perso il focus.
        return _TvRowSlot(
          key: card.key == null ? null : ValueKey(card.key),
          index: i,
          row: this,
          child: child,
        );
      },
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

/// Sulla TV, il posto [index] di una riga: segna il suo nodo nella riga e le
/// dice quando il focus esce e quando viene smontato.
class _TvRowSlot extends StatefulWidget {
  const _TvRowSlot({
    super.key,
    required this.index,
    required this.row,
    required this.child,
  });

  final int index;
  final _MediaRowState row;
  final Widget child;

  @override
  State<_TvRowSlot> createState() => _TvRowSlotState();
}

class _TvRowSlotState extends State<_TvRowSlot> {
  final _node = FocusNode(canRequestFocus: false, skipTraversal: true);

  /// Il focus è dentro. Resta vero se la card col focus viene smontata
  /// insieme allo slot: il cambio di focus arriva dopo.
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.row._tvSlots[widget.index] = _node;
  }

  @override
  void didUpdateWidget(_TvRowSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    if (widget.row._tvSlots[oldWidget.index] == _node) {
      widget.row._tvSlots.remove(oldWidget.index);
    }
    widget.row._tvSlots[widget.index] = _node;
  }

  @override
  void dispose() {
    final slots = widget.row._tvSlots;
    if (slots[widget.index] == _node) slots.remove(widget.index);
    widget.row._slotGone(widget.index, _node, focused: _focused);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _node,
    onFocusChange: (focused) {
      _focused = focused;
      if (!focused) widget.row._slotBlurred(widget.index, _node);
    },
    child: widget.child,
  );
}
