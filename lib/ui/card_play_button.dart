import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/theme.dart';
import '../l10n/gen/app_localizations.dart';

/// Pulsante tondo "Riproduci" da centrare sull'immagine di una card
/// mentre il mouse ci passa sopra.
class CardPlayButton extends StatelessWidget {
  const CardPlayButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: AppLocalizations.of(context).actionPlay,
      // Il GestureDetector interno vince l'arena contro quello della card:
      // il tap sul pulsante non apre il dettaglio.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: size,
          height: size,
          decoration:
              const BoxDecoration(color: WfColors.gold, shape: BoxShape.circle),
          child: const Icon(LucideIcons.play, size: 22, color: WfColors.bg),
        ),
      ),
    );
  }
}
