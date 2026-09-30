import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sosta del mouse su una card prima che si apra l'anteprima (spec C §7.1).
const previewHoverDelay = Duration(milliseconds: 500);

/// Entro questo tempo dalla chiusura di un'anteprima, la card su cui passa
/// il mouse apre la sua subito (passaggio da una card all'altra).
const previewChainWindow = Duration(milliseconds: 400);

/// Larghezza dell'anteprima rispetto alla card, e minimo (spec C §7.2).
const previewWidthFactor = 1.8;
const previewMinWidth = 300.0;

/// Altezza della parte sotto l'immagine 16:9: pulsanti, dati, generi,
/// avanzamento.
const previewBodyHeight = 124.0;

/// Distanza minima dai bordi della finestra.
const previewMargin = 16.0;

/// Rettangolo dell'anteprima di una card: centrata sulla card, larga
/// [previewWidthFactor] volte (almeno [previewMinWidth]), dentro l'overlay
/// con [previewMargin] di margine.
Rect previewRect({required Rect card, required Size overlay}) {
  final maxWidth = math.max(0.0, overlay.width - 2 * previewMargin);
  final width = math
      .max(previewMinWidth, card.width * previewWidthFactor)
      .clamp(0.0, maxWidth)
      .toDouble();
  final height = width * 9 / 16 + previewBodyHeight;
  final left = (card.center.dx - width / 2).clamp(
      previewMargin, math.max(previewMargin, overlay.width - previewMargin - width));
  final top = (card.center.dy - height / 2).clamp(
      previewMargin, math.max(previewMargin, overlay.height - previewMargin - height));
  return Rect.fromLTWH(left.toDouble(), top.toDouble(), width, height);
}

/// Quale anteprima è aperta (al massimo una) e quando si è chiusa l'ultima.
@immutable
class CardPreviewState {
  const CardPreviewState({this.openId, this.closedAt});

  /// Identità della card che mostra l'anteprima (lo stato del suo host).
  final Object? openId;
  final DateTime? closedAt;
}

class CardPreviewController extends Notifier<CardPreviewState> {
  @override
  CardPreviewState build() => const CardPreviewState();

  void open(Object id) => state = CardPreviewState(openId: id);

  /// Chiude l'anteprima di [id], se è quella aperta.
  void close(Object id) {
    if (!identical(state.openId, id)) return;
    state = CardPreviewState(closedAt: clock.now());
  }

  /// Un'anteprima è aperta o si è appena chiusa: la prossima si apre subito.
  bool opensImmediately() {
    if (state.openId != null) return true;
    final closed = state.closedAt;
    return closed != null && clock.now().difference(closed) < previewChainWindow;
  }
}

final cardPreviewProvider =
    NotifierProvider<CardPreviewController, CardPreviewState>(
        CardPreviewController.new);
