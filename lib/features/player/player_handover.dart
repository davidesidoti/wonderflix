import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Player da solo che il routing del watch party sostituisce con quello del
/// gruppo ("Guarda insieme", o la coda del gruppo arrivata con il player
/// aperto). Chiudendosi, il player sostituito fa come passando all'episodio
/// dopo: non esce dallo schermo intero e non nasconde il pannello media (né
/// il gruppo su Discord), che passano al player nuovo.
class PlayerHandover {
  String? _itemId;

  /// Il player da solo di [itemId] sta per essere sostituito.
  void replacing(String itemId) => _itemId = itemId;

  /// `true`, una volta sola, se il player da solo di [itemId] è stato
  /// sostituito dal routing.
  bool consume(String itemId) {
    if (_itemId != itemId) return false;
    _itemId = null;
    return true;
  }
}

final playerHandoverProvider =
    Provider<PlayerHandover>((ref) => PlayerHandover());
