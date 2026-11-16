import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/theme.dart';
import 'form_factor.dart';

/// Il velo dietro le finestre: il nero dell'app, quasi opaco.
const _barrier = Color(0xB30A0A0A);

/// Una finestra dell'app (decisione 2 del piano 15b): fondo `surface`,
/// bordo, angoli arrotondati, larga al massimo [maxWidth]. Esc e il clic
/// fuori la chiudono con `null`. Con [semanticLabel] (di solito il titolo)
/// lo screen reader annuncia la finestra quando si apre; senza, la annuncia
/// con il nome predefinito di Material, come `AlertDialog`.
///
/// Nel layout stretto, con [fullPageWhenCompact], la finestra è una pagina
/// intera sul navigatore radice, con una barra alta 56: [compactTitle] e la
/// ✕ (che chiude con `maybePop`, quindi passa da `WfDiscardGuard`).
///
/// Con [footer] (di solito un `WfDialogFooter`) il corpo scorre e il piede
/// resta fisso sotto, a tutta larghezza (nello stretto sopra la tastiera).
/// Senza, il corpo deve poter scorrere o stare nello spazio sopra la
/// tastiera da sé, come prima.
Future<T?> showWfDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 480,
  String? semanticLabel,
  bool fullPageWhenCompact = true,
  EdgeInsets padding = const EdgeInsets.all(24),
  String? compactTitle,
  WidgetBuilder? footer,
}) {
  if (fullPageWhenCompact && FormFactor.of(context).compact) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<T>(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: WfColors.surface,
          body: SafeArea(
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label:
                  semanticLabel ??
                  MaterialLocalizations.of(context).dialogLabel,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            compactTitle ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WfText.display(26),
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).closeButtonTooltip,
                          icon: const Icon(LucideIcons.x),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: footer == null
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Builder(builder: builder),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Builder(builder: builder),
                          ),
                  ),
                  if (footer != null) Builder(builder: footer),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierColor: _barrier,
    builder: (context) => Dialog(
      backgroundColor: WfColors.surface,
      surfaceTintColor: Colors.transparent,
      // Il contenuto che arriva ai bordi (padding zero) resta negli angoli.
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: WfColors.border),
      ),
      // Come `AlertDialog`: la finestra è un ambito a sé e dà il nome alla rotta.
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: semanticLabel ?? MaterialLocalizations.of(context).dialogLabel,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: footer == null
              ? Padding(padding: padding, child: Builder(builder: builder))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        padding: padding,
                        child: Builder(builder: builder),
                      ),
                    ),
                    Builder(builder: footer),
                  ],
                ),
        ),
      ),
    ),
  );
}
