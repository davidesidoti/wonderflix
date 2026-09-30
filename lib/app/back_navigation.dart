import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/update/update_gate.dart';
import '../ui/card_preview.dart';

/// Esc, Alt+← e il tasto "indietro" del mouse chiudono la pagina corrente.
/// Non fa nulla se sopra c'è un menu o un dialog (gestiscono loro Esc) o la
/// schermata dell'aggiornamento obbligatorio; con un'anteprima di una card
/// aperta Esc chiude solo l'anteprima.
class BackNavigationHandler extends ConsumerStatefulWidget {
  const BackNavigationHandler({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BackNavigationHandler> createState() =>
      _BackNavigationHandlerState();
}

class _BackNavigationHandlerState extends ConsumerState<BackNavigationHandler> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    // Con un'anteprima aperta Esc chiude solo lei (lo gestisce l'anteprima):
    // tutti i gestori ricevono il tasto, qui la pagina resta.
    if (key == LogicalKeyboardKey.escape &&
        ref.read(cardPreviewProvider).openId != null) {
      return false;
    }
    final isBack = key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack ||
        (key == LogicalKeyboardKey.arrowLeft &&
            HardwareKeyboard.instance.isAltPressed);
    return isBack && _goBack();
  }

  bool _goBack() {
    if (!mounted) return false;
    if (ref.read(updateBlockedProvider)) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final router = GoRouter.maybeOf(context);
    if (router == null || !router.canPop()) return false;
    router.pop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (event.buttons & kBackMouseButton != 0) _goBack();
      },
      child: widget.child,
    );
  }
}
