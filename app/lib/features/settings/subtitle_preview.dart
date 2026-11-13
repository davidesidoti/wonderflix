import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';

/// Riquadro 16:9 che mostra una frase come la vedrebbe il player con la
/// dimensione [scale] dei sottotitoli: senza video né rete, si aggiorna mentre
/// si cambia la dimensione. Prende la larghezza che trova.
class SubtitlePreview extends StatelessWidget {
  const SubtitlePreview({super.key, required this.scale});

  /// Una delle `subtitleScaleOptions`.
  final double scale;

  /// La `sub-font-size` predefinita di mpv, a 720 righe di video.
  static const _mpvFontSize = 55.0;

  /// Dimensione del testo in un riquadro alto [height]: la stessa proporzione
  /// del player.
  static double fontSizeFor(double height, double scale) =>
      _mpvFontSize * height / 720 * scale;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(builder: (context, box) {
        final size = fontSizeFor(box.maxHeight, scale);
        // Il contorno è fatto di ombre senza sfocatura: sul chiaro del
        // fondo il bianco resta leggibile.
        final r = (size * 0.07).clamp(0.5, 2.0);
        final outline = [
          for (final (dx, dy) in const [
            (-1.0, -1.0), (0.0, -1.0), (1.0, -1.0), (-1.0, 0.0), //
            (1.0, 0.0), (-1.0, 1.0), (0.0, 1.0), (1.0, 1.0),
          ])
            Shadow(color: Colors.black, offset: Offset(dx * r, dy * r)),
        ];
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF26303A),
                      Color(0xFF3C3428),
                      Color(0xFF14110D),
                    ],
                    stops: [0, 0.55, 1],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.4, -0.4),
                    radius: 0.9,
                    colors: [Color(0x40FFD28C), Color(0x00FFD28C)],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: box.maxHeight * 0.1,
                child: Text(
                  AppLocalizations.of(context).settingsSubtitlePreviewSample,
                  key: const Key('subtitle-preview-text'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size,
                    fontWeight: FontWeight.w600,
                    shadows: outline,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: WfColors.border),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
