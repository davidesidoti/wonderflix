import 'package:flutter/material.dart';

import 'theme.dart';

/// Mostrata quando l'app è stata compilata senza `config/wonderflix.json`.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildWonderflixTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Configurazione mancante.\n\n$message\n\n'
              'Avvia con: flutter run -d windows '
              '--dart-define-from-file=config/wonderflix.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
