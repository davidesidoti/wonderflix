import 'package:flutter/widgets.dart';

import 'form_factor.dart';
import 'tv_focusable.dart';

/// Sulla TV un campo di testo che il telecomando attraversa senza aprire la
/// tastiera: il fuoco si ferma sulla cornice ([TvFocusable]) e solo OK dà il
/// fuoco al campo. Sul Fire TV il campo apre la tastiera appena ha il fuoco,
/// e chiudendola il fuoco salta via: senza cornice non si passa oltre.
/// [focusNode] è quello del campo dentro [child]. Fuori dalla TV restituisce
/// [child].
class TvTextFieldFrame extends StatefulWidget {
  const TvTextFieldFrame(
      {super.key, required this.focusNode, required this.child});

  final FocusNode focusNode;
  final Widget child;

  @override
  State<TvTextFieldFrame> createState() => TvTextFieldFrameState();
}

class TvTextFieldFrameState extends State<TvTextFieldFrame> {
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (!widget.focusNode.hasFocus && _typing) setState(() => _typing = false);
  }

  /// Dà il fuoco al campo (e la tastiera): OK sulla cornice, o "Avanti" dal
  /// campo precedente.
  void startTyping() {
    setState(() => _typing = true);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.focusNode.requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    if (!FormFactor.of(context).tv) return widget.child;
    return TvFocusable(
      onActivate: startTyping,
      child: ExcludeFocus(excluding: !_typing, child: widget.child),
    );
  }
}
