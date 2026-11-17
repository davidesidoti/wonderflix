import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Sulla TV una pagina fatta di file ([TvLane]) una sotto l'altra: Su e Giù
/// vanno alla fila prima o dopo, anche se è corta (Flutter salterebbe una
/// fila che non sta sotto la carta col focus), sulla carta più vicina per il
/// bordo sinistro; Destra e Sinistra restano nella fila, e Destra si ferma
/// all'ultima carta. Sinistra sulla prima carta passa oltre (la barra).
class TvLanes extends StatefulWidget {
  const TvLanes({super.key, required this.child});

  final Widget child;

  @override
  State<TvLanes> createState() => _TvLanesState();
}

class _TvLanesState extends State<TvLanes> {
  final _page = FocusNode(canRequestFocus: false, skipTraversal: true);

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final vertical =
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    final horizontal =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    final current = FocusManager.instance.primaryFocus;
    if ((!vertical && !horizontal) || current == null) {
      return KeyEventResult.ignored;
    }
    final lane = current.ancestors.whereType<_LaneNode>().firstOrNull;
    if (lane == null) return KeyEventResult.ignored;
    final left = current.rect.left;
    if (horizontal) {
      // Nel campo di testo le frecce muovono il cursore.
      if (current.context?.findAncestorWidgetOfExactType<EditableText>() !=
          null) {
        return KeyEventResult.ignored;
      }
      final right = key == LogicalKeyboardKey.arrowRight;
      final next = _nearest(
        lane.traversalDescendants.where(
          (n) => right ? n.rect.left > left + 1 : n.rect.left < left - 1,
        ),
        left,
      );
      if (next == null) {
        return right ? KeyEventResult.handled : KeyEventResult.ignored;
      }
      _focus(next, right ? TraversalDirection.right : TraversalDirection.left);
      return KeyEventResult.handled;
    }
    final lanes = [
      for (final node in _page.descendants)
        if (node is _LaneNode && node.traversalDescendants.isNotEmpty) node,
    ]..sort((a, b) => a.rect.top.compareTo(b.rect.top));
    final down = key == LogicalKeyboardKey.arrowDown;
    final index = lanes.indexOf(lane) + (down ? 1 : -1);
    if (index < 0 || index >= lanes.length) return KeyEventResult.ignored;
    final target = lanes[index];
    final direction = down ? TraversalDirection.down : TraversalDirection.up;
    final onEnter = target.lane?.onEnter;
    if (onEnter != null) {
      // La fila torna all'inizio: la prima carta si costruisce al frame dopo.
      onEnter();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // La fila può essere sparita intanto (risultati nuovi).
        if (target.disposed) return;
        // La più a sinistra: l'ordine dei nodi cambia con le ricostruzioni.
        final first = _nearest(target.traversalDescendants, target.rect.left);
        if (first != null) _focus(first, direction);
      });
      // Con la fila già a 0 nessuno chiederebbe il frame.
      WidgetsBinding.instance.ensureVisualUpdate();
    } else {
      _focus(_nearest(target.traversalDescendants, left)!, direction);
    }
    return KeyEventResult.handled;
  }

  static FocusNode? _nearest(Iterable<FocusNode> nodes, double left) {
    FocusNode? best;
    for (final node in nodes) {
      if (best == null ||
          (node.rect.left - left).abs() < (best.rect.left - left).abs()) {
        best = node;
      }
    }
    return best;
  }

  /// Come la navigazione di Flutter: focus e scorrimento fino a vederla.
  static void _focus(FocusNode node, TraversalDirection direction) =>
      FocusTraversalPolicy.defaultTraversalRequestFocusCallback(
        node,
        alignmentPolicy:
            direction == TraversalDirection.up ||
                direction == TraversalDirection.left
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _page, onKeyEvent: _onKey, child: widget.child);
}

/// [node] sta in una [TvLane]: Sinistra sulla sua prima carta (che [TvLanes]
/// lascia passare) va alla barra, non in un'altra fila più a sinistra.
bool isInTvLane(FocusNode node) => node.ancestors.any((n) => n is _LaneNode);

/// Una fila di una [TvLanes]. Con [onEnter] chi arriva da un'altra fila
/// va alla prima carta, dopo [onEnter] (per esempio la fila torna a 0).
class TvLane extends StatefulWidget {
  const TvLane({super.key, required this.child, this.onEnter});

  final Widget child;
  final VoidCallback? onEnter;

  @override
  State<TvLane> createState() => _TvLaneState();
}

class _LaneNode extends FocusNode {
  _LaneNode() : super(canRequestFocus: false, skipTraversal: true);

  TvLane? lane;
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _TvLaneState extends State<TvLane> {
  final _node = _LaneNode();

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _node.lane = widget;
    return Focus(focusNode: _node, child: widget.child);
  }
}
