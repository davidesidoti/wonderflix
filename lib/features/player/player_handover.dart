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

/// Il pannello "Coda" del watch party (spec H §9.1) aperto nel player che il
/// gruppo sostituisce con quello del titolo dopo (qualcuno ha saltato a una
/// riga, o la coda è andata avanti): il player nuovo ha un suo stato dei
/// riquadri, e senza questo il pannello sparirebbe a ogni cambio di titolo.
/// Chi lascia segna se era aperto, chi arriva lo legge, una volta sola.
class PartyQueuePanelCarry {
  bool _open = false;

  /// Il player che sta per essere sostituito dice se il pannello era aperto.
  void carry({required bool open}) => _open = open;

  /// `true`, una volta sola, se il pannello va riaperto nel player nuovo.
  bool take() {
    final open = _open;
    _open = false;
    return open;
  }
}

final partyQueuePanelCarryProvider =
    Provider<PartyQueuePanelCarry>((ref) => PartyQueuePanelCarry());
