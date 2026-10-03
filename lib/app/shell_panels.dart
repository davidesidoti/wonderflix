import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/friends/friends_controller.dart';
import '../features/inbox/inbox_controller.dart';

/// I pannelli laterali della shell (spec F §8.3, spec G §7.5).
enum ShellPanel { none, friends, inbox }

/// Il pannello laterale aperto: uno alla volta, aprirne uno chiude l'altro.
/// Aprire Amici rilegge gli amici; aprire e chiudere Notifiche lo dice alla
/// cassetta (letture e pallini). Non dipende da altri provider: lo legge
/// anche la gestione dei tasti indietro. Si azzera quando nessuno lo guarda
/// più (es. la shell smontata al logout).
class ShellPanelController extends Notifier<ShellPanel> {
  @override
  ShellPanel build() => ShellPanel.none;

  void open(ShellPanel panel) {
    if (panel == ShellPanel.none) {
      close();
      return;
    }
    if (state == panel) return;
    _leaving();
    state = panel;
    switch (panel) {
      case ShellPanel.friends:
        unawaited(ref.read(friendsControllerProvider.notifier).reload());
      case ShellPanel.inbox:
        ref.read(inboxControllerProvider.notifier).panelOpened();
      case ShellPanel.none:
        break;
    }
  }

  void close() {
    if (state == ShellPanel.none) return;
    _leaving();
    state = ShellPanel.none;
  }

  void toggle(ShellPanel panel) => state == panel ? close() : open(panel);

  /// Il pannello di adesso sta per chiudersi.
  void _leaving() {
    if (state == ShellPanel.inbox) {
      ref.read(inboxControllerProvider.notifier).panelClosed();
    }
  }
}

final shellPanelProvider =
    NotifierProvider.autoDispose<ShellPanelController, ShellPanel>(
        ShellPanelController.new);
