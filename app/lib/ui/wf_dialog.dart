import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../l10n/gen/app_localizations.dart';
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
/// intera sul navigatore radice, con la freccia indietro (che chiude con
/// `null`); il contenuto deve poter scorrere o stare nello spazio sopra la
/// tastiera.
Future<T?> showWfDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 480,
  String? semanticLabel,
  bool fullPageWhenCompact = true,
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
              label: semanticLabel ??
                  MaterialLocalizations.of(context).dialogLabel,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: AppLocalizations.of(context).navBack,
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Builder(builder: builder),
                    ),
                  ),
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
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    );
}
