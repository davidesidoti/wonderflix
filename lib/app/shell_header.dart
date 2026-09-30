part of 'app_shell.dart';

// Canale tra le pagine e la barra della shell: stato "scorsa" e titolo
// della pagina in cima (spec C §9.2, §11.1). È una parte di app_shell.dart
// perché AppShell e le pagine condividono membri privati (_ShellBarScope,
// _BarTitle, _ShellPageFrameState) che non devono diventare API pubblica.

/// Porta alle pagine della shell i valori della barra: "pagina scorsa" e
/// titolo della pagina.
class _ShellBarScope extends InheritedWidget {
  const _ShellBarScope({
    required this.scrolled,
    required this.header,
    required super.child,
  });

  final ValueNotifier<bool> scrolled;
  final ValueNotifier<ShellHeader?> header;

  @override
  bool updateShouldNotify(_ShellBarScope oldWidget) =>
      oldWidget.scrolled != scrolled || oldWidget.header != header;
}

/// Titolo e azione della pagina mostrati nella barra quando la sua testata
/// è uscita dallo schermo (spec C §9.2).
@immutable
class ShellHeader {
  const ShellHeader({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  // L'uguaglianza ignora il callback: cambia a ogni build.
  @override
  bool operator ==(Object other) =>
      other is ShellHeader &&
      other.title == title &&
      other.actionLabel == actionLabel;

  @override
  int get hashCode => Object.hash(title, actionLabel);
}

/// Contenuto di una pagina della shell (lo aggiungono `shellPage` e
/// `detailPage`). Lascia il margine sotto la barra se [underBar]; altrimenti
/// la pagina arriva al bordo della finestra (Home e scheda, spec C §11.1).
///
/// Ricorda se la propria pagina è scorsa e il suo titolo per la barra
/// ([ShellHeaderPublisher]) e, quando la sua rotta è in cima, li dice alla
/// barra: tornando indietro la barra ritrova lo stato e il titolo della
/// pagina, e una pagina nuova parte chiara e senza titolo.
class ShellPageFrame extends StatefulWidget {
  const ShellPageFrame(
      {super.key, required this.underBar, required this.child});

  final bool underBar;
  final Widget child;

  @override
  State<ShellPageFrame> createState() => _ShellPageFrameState();
}

class _ShellPageFrameState extends State<ShellPageFrame> {
  ValueNotifier<bool>? _barScrolled;
  ValueNotifier<ShellHeader?>? _barHeader;
  bool _scrolled = false;
  ShellHeader? _pageHeader;
  bool _current = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.getInheritedWidgetOfExactType<_ShellBarScope>();
    _barScrolled = scope?.scrolled;
    _barHeader = scope?.header;
    // Dipende dalla rotta: si riesegue quando torna in cima.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    final becameCurrent = current && !_current;
    _current = current;
    if (becameCurrent) _publish();
  }

  bool _onScroll(ScrollNotification notification) {
    // Solo lo scroll verticale della pagina, non le righe orizzontali.
    if (notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical) {
      final scrolled = notification.metrics.pixels > 4;
      if (scrolled != _scrolled) {
        _scrolled = scrolled;
        if (_current) _publish();
      }
    }
    return false;
  }

  void _setHeader(ShellHeader? header) {
    _pageHeader = header;
    if (_current) _publish();
  }

  /// Scrive stato e titolo nella barra; durante la costruzione (la shell è
  /// un antenato) aspetta la fine del fotogramma.
  void _publish() {
    void write() {
      if (!mounted || !_current) return;
      _barScrolled?.value = _scrolled;
      _barHeader?.value = _pageHeader;
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => write());
    } else {
      write();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: widget.underBar ? shellBarHeight : 0),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
      );
}

/// Pubblica [header] nella barra quando lo scroll di [controller] supera
/// [threshold], e lo toglie sotto la soglia o alla chiusura.
class ShellHeaderPublisher extends StatefulWidget {
  const ShellHeaderPublisher({
    super.key,
    required this.controller,
    required this.threshold,
    required this.header,
    required this.child,
  });

  final ScrollController controller;
  final double threshold;

  /// `null` finché non si sa cosa mostrare.
  final ShellHeader? header;
  final Widget child;

  @override
  State<ShellHeaderPublisher> createState() => _ShellHeaderPublisherState();
}

class _ShellHeaderPublisherState extends State<ShellHeaderPublisher> {
  _ShellPageFrameState? _frame;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _frame = context.findAncestorStateOfType<_ShellPageFrameState>();
  }

  @override
  void didUpdateWidget(ShellHeaderPublisher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    if (_shown && oldWidget.header != widget.header) {
      _frame?._setHeader(widget.header);
    }
  }

  void _onScroll() {
    final controller = widget.controller;
    final shown =
        controller.hasClients && controller.offset >= widget.threshold;
    if (shown == _shown) return;
    _shown = shown;
    _frame?._setHeader(shown ? widget.header : null);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    if (_shown) _frame?._setHeader(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Titolo e piccolo "Riproduci" della pagina in cima (spec C §9.2).
class _BarTitle extends StatelessWidget {
  const _BarTitle({required this.header});

  final ValueNotifier<ShellHeader?> header;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    return Flexible(
      child: ValueListenableBuilder<ShellHeader?>(
        valueListenable: header,
        builder: (context, value, _) => AnimatedSwitcher(
          duration: motion.duration(WfMotion.medium),
          switchInCurve: WfMotion.emphasized,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
                  .animate(animation),
              child: child,
            ),
          ),
          child: value == null
              ? const SizedBox.shrink()
              : Row(
                  key: const Key('shell-bar-title'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(value.title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WfText.display(22)),
                    ),
                    if (value.onAction != null) ...[
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        key: const Key('shell-bar-play'),
                        onPressed: value.onAction,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        icon: const Icon(LucideIcons.play, size: 14),
                        label: Text(value.actionLabel ?? ''),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
