import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/tv_focusable.dart';

/// Larghezza del pannello delle scelte sulla TV.
const tvChoicePanelWidth = 300.0;

/// Sulla TV apre, a tutto schermo, il pannello delle scelte da destra: Su e
/// Giù scelgono (il focus parte da [current]), OK conferma e chiude con la
/// scelta, Indietro chiude senza (`null`). [background], se c'è, riempie il
/// resto dello schermo e riceve l'opzione col focus (l'anteprima dei
/// sottotitoli).
Future<T?> showTvChoicePanel<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T current,
  Widget Function(T focused)? background,
}) {
  // Sul navigatore radice: copre anche la barra laterale. Indietro lo chiude
  // il `PopScope` della rotta (mai `goBack` nei tasti).
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<T>(
      opaque: false,
      barrierColor: background == null ? Colors.black54 : null,
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, _, _) => _TvChoicePanel<T>(
        title: title,
        options: options,
        current: current,
        background: background,
      ),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _TvChoicePanel<T> extends StatefulWidget {
  const _TvChoicePanel({
    required this.title,
    required this.options,
    required this.current,
    required this.background,
  });

  final String title;
  final List<(T, String)> options;
  final T current;
  final Widget Function(T focused)? background;

  @override
  State<_TvChoicePanel<T>> createState() => _TvChoicePanelState<T>();
}

class _TvChoicePanelState<T> extends State<_TvChoicePanel<T>> {
  late T _focused = widget.current;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final background = widget.background;
    return Stack(
      children: [
        if (background != null)
          Positioned.fill(
            right: tvChoicePanelWidth,
            child: ColoredBox(
              color: WfColors.bg,
              child: Center(child: background(_focused)),
            ),
          ),
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: tvChoicePanelWidth,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xF7121212),
              border: Border(left: BorderSide(color: WfColors.border)),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 40, 26, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.title, style: WfText.display(24)),
                    const SizedBox(height: 12),
                    for (final (value, label) in widget.options)
                      _option(value, label),
                    const SizedBox(height: 14),
                    Text(
                      l.tvSettingsBackToClose,
                      style: const TextStyle(
                        color: WfColors.creamMuted,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _option(T value, String label) {
    final focused = value == _focused;
    return TvFocusable(
      key: ValueKey('tv-choice-$value'),
      // La rotta è uno scope nuovo: qui `autofocus` vale.
      autofocus: value == widget.current,
      onFocusChange: (on) {
        if (on) setState(() => _focused = value);
      },
      onActivate: () => Navigator.of(context).pop(value),
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 34, right: 14),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: focused ? WfColors.surfaceHigh : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: [
            if (value == widget.current)
              const Positioned(
                left: -21,
                child: SizedBox.square(
                  key: Key('tv-choice-current'),
                  dimension: 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: WfColors.gold,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
