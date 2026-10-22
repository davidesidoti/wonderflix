import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../app/app_shell.dart';
import 'detail_header.dart';

/// Velocità dello sfondo rispetto al contenuto (spec C §9.1).
const parallaxFactor = 0.5;

/// Zoom massimo dello sfondo e scurimento massimo.
const parallaxMaxZoom = 0.08;
const parallaxMaxDim = 0.5;

/// Il testo della testata sparisce a questa frazione di testata scorsa.
const parallaxTextFadeEnd = 0.625;

/// Salita del testo rispetto allo scroll.
const parallaxTextRise = 0.15;

/// Con le animazioni complete il titolo va nella barra quando l'opacità del
/// testo della testata scende a questo valore (≈ 245 px di scroll).
const barTitleTextOpacity = 0.3;

/// Con le animazioni ridotte il testo non sfuma: il titolo va nella barra
/// quando la riga dei pulsanti della testata passa sotto la barra (468 px).
const detailBarTitleReducedOffset =
    detailHeaderHeight - detailHeaderTextBottom - shellBarHeight;

/// Il titolo e "Riproduci" compaiono nella barra quando il testo della
/// testata è quasi sparito (spec C §9.2, decisione della prova 6b).
bool barTitleVisible(double offset, {required bool reduced}) {
  if (reduced) return offset >= detailBarTitleReducedOffset;
  return headerParallax(offset, reduced: false).textOpacity <=
      barTitleTextOpacity;
}

/// Posizione della testata per uno scroll (spec C §9.1).
@immutable
class HeaderParallax {
  const HeaderParallax({
    required this.backdropShift,
    required this.backdropScale,
    required this.dim,
    required this.textOpacity,
    required this.textShift,
    required this.visibleHeight,
  });

  /// Spostamento verticale dello sfondo.
  final double backdropShift;
  final double backdropScale;

  /// Opacità del velo scuro sopra lo sfondo.
  final double dim;
  final double textOpacity;
  final double textShift;

  /// Parte della testata ancora sullo schermo: lo sfondo si ritaglia lì,
  /// altrimenti sporgerebbe dietro alle righe sotto.
  final double visibleHeight;
}

HeaderParallax headerParallax(double offset, {required bool reduced}) {
  final o = math.max(0.0, offset);
  final visible = (detailHeaderHeight - o).clamp(0.0, detailHeaderHeight);
  if (reduced) {
    return HeaderParallax(
      backdropShift: -o,
      backdropScale: 1,
      dim: 0,
      textOpacity: 1,
      textShift: 0,
      visibleHeight: visible,
    );
  }
  final k = (o / detailHeaderHeight).clamp(0.0, 1.0);
  return HeaderParallax(
    backdropShift: -o * parallaxFactor,
    backdropScale: 1 + parallaxMaxZoom * k,
    dim: parallaxMaxDim * k,
    textOpacity: (1 - k / parallaxTextFadeEnd).clamp(0.0, 1.0),
    textShift: -o * parallaxTextRise,
    visibleHeight: visible,
  );
}
