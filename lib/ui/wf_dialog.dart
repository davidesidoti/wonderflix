import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Il velo dietro le finestre: il nero dell'app, quasi opaco.
const _barrier = Color(0xB30A0A0A);

/// Una finestra dell'app (decisione 2 del piano 15b): fondo `surface`,
/// bordo, angoli arrotondati, larga al massimo [maxWidth]. Esc e il clic
/// fuori la chiudono con `null`. Con [semanticLabel] (di solito il titolo)
/// lo screen reader annuncia la finestra quando si apre; senza, la annuncia
/// con il nome predefinito di Material, come `AlertDialog`.
Future<T?> showWfDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 480,
  String? semanticLabel,
}) =>
    showDialog<T>(
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
