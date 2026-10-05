import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Il velo dietro le finestre: il nero dell'app, quasi opaco.
const _barrier = Color(0xB30A0A0A);

/// Una finestra dell'app (decisione 2 del piano 15b): fondo `surface`,
/// bordo, angoli arrotondati, larga al massimo [maxWidth]. Esc e il clic
/// fuori la chiudono con `null`.
Future<T?> showWfDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 480,
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
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Builder(builder: builder),
          ),
        ),
      ),
    );
