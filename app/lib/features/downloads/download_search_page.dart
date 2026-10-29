import 'package:flutter/material.dart';

/// La pagina a tutto schermo con le release di un titolo (spec T §8.2).
/// Segnaposto: il corpo vero arriva con il compito 4 del piano 29b.
Future<void> showDownloadSearch(
  BuildContext context,
  String key,
  String title, {
  bool reviewing = false,
}) =>
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(title),
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
