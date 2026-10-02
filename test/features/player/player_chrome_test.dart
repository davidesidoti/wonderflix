import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/player/player_chrome.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';

void main() {
  const duration = Duration(minutes: 40);
  const step = Duration(seconds: 10);

  test('in riproduzione i controlli spariscono dopo 3 s; il mouse li riporta',
      () {
    fakeAsync((async) {
      final chrome = PlayerChromeController();
      var notified = 0;
      chrome.addListener(() => notified++);
      expect(chrome.controlsVisible, isTrue);
      chrome.setPlayback(playing: true, canShowPauseScreen: false);
      async.elapse(const Duration(milliseconds: 2900));
      expect(chrome.controlsVisible, isTrue);
      async.elapse(const Duration(milliseconds: 100));
      expect(chrome.controlsVisible, isFalse);
      expect(notified, 1);

      chrome.pointerActivity();
      expect(chrome.controlsVisible, isTrue);
      async.elapse(const Duration(seconds: 2));
      chrome.pointerActivity(); // il conto riparte
      async.elapse(const Duration(seconds: 2));
      expect(chrome.controlsVisible, isTrue);
      async.elapse(const Duration(seconds: 1));
      expect(chrome.controlsVisible, isFalse);
      chrome.dispose();
    });
  });

  test('in riproduzione un tasto non tiene su i controlli', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: true, canShowPauseScreen: false);
      async.elapse(const Duration(milliseconds: 2500));
      chrome.keyActivity(); // tenendo premuta una freccia, per esempio
      async.elapse(const Duration(milliseconds: 500));
      expect(chrome.controlsVisible, isFalse,
          reason: 'il conto dei 3 s non riparte dal tasto');
      chrome.dispose();
    });
  });

  test('in pausa i controlli restano', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: true, canShowPauseScreen: false);
      async.elapse(const Duration(seconds: 1));
      chrome.setPlayback(playing: false, canShowPauseScreen: false);
      async.elapse(const Duration(seconds: 10));
      expect(chrome.controlsVisible, isTrue);
      chrome.dispose();
    });
  });

  test('pannello aperto: i controlli restano; chiuso, il conto riparte', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: true, canShowPauseScreen: false);
      async.elapse(const Duration(seconds: 5));
      expect(chrome.controlsVisible, isFalse);
      chrome.togglePanel();
      expect(chrome.panelOpen, isTrue);
      expect(chrome.controlsVisible, isTrue);
      async.elapse(const Duration(seconds: 10));
      expect(chrome.controlsVisible, isTrue);
      chrome.closePanel();
      expect(chrome.panelOpen, isFalse);
      async.elapse(PlayerChromeController.hideDelay);
      expect(chrome.controlsVisible, isFalse);
      chrome.dispose();
    });
  });

  test('riscontro: resta 1,2 s dall\'ultimo tasto e non mostra i controlli',
      () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: true, canShowPauseScreen: false);
      async.elapse(const Duration(seconds: 3));
      chrome.showFeedback(const VolumeFeedback(volume: 70, muted: false));
      expect(chrome.feedback, isA<VolumeFeedback>());
      expect(chrome.controlsVisible, isFalse);
      async.elapse(const Duration(seconds: 1));
      chrome.showFeedback(const VolumeFeedback(volume: 75, muted: false));
      async.elapse(const Duration(seconds: 1));
      expect((chrome.feedback! as VolumeFeedback).volume, 75);
      async.elapse(const Duration(milliseconds: 200));
      expect(chrome.feedback, isNull);
      chrome.dispose();
    });
  });

  test('salti: si sommano nella stessa direzione entro 1 s', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController();
      chrome.seek(step, from: const Duration(minutes: 17), duration: duration);
      async.elapse(const Duration(milliseconds: 500));
      // La posizione del motore può essere ancora quella di prima: conta
      // l'arrivo del salto precedente.
      chrome.seek(step, from: const Duration(minutes: 17), duration: duration);
      var seek = chrome.feedback! as SeekFeedback;
      expect(seek.offset, const Duration(seconds: 20));
      expect(seek.target, const Duration(minutes: 17, seconds: 20));

      // Direzione opposta: si ricomincia.
      chrome.seek(-step,
          from: const Duration(minutes: 17, seconds: 20), duration: duration);
      seek = chrome.feedback! as SeekFeedback;
      expect(seek.offset, -step);
      expect(seek.target, const Duration(minutes: 17, seconds: 10));

      // Oltre 1 s: si ricomincia.
      async.elapse(const Duration(milliseconds: 1100));
      chrome.seek(-step,
          from: const Duration(minutes: 17, seconds: 10), duration: duration);
      seek = chrome.feedback! as SeekFeedback;
      expect(seek.offset, -step);
      expect(seek.target, const Duration(minutes: 17));
      chrome.dispose();
    });
  });

  test('salti: arrivo tra 0 e la durata', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController();
      chrome.seek(-step, from: const Duration(seconds: 4), duration: duration);
      expect((chrome.feedback! as SeekFeedback).target, Duration.zero);
      async.elapse(const Duration(seconds: 2));
      chrome.seek(step,
          from: const Duration(minutes: 39, seconds: 55), duration: duration);
      expect((chrome.feedback! as SeekFeedback).target, duration);
      chrome.dispose();
    });
  });

  test('azione recente da tastiera: stesso tipo, entro 1 s', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController();
      expect(chrome.isRecentKeyAction(PartyNoticeKind.paused), isFalse);
      chrome.showFeedback(const PlayFeedback(playing: false));
      expect(chrome.isRecentKeyAction(PartyNoticeKind.paused), isTrue);
      expect(chrome.isRecentKeyAction(PartyNoticeKind.resumed), isFalse);
      expect(chrome.isRecentKeyAction(PartyNoticeKind.seeked), isFalse);
      chrome.seek(step, from: Duration.zero, duration: duration);
      async.elapse(const Duration(milliseconds: 400));
      expect(chrome.isRecentKeyAction(PartyNoticeKind.seeked), isTrue);
      async.elapse(const Duration(milliseconds: 700));
      expect(chrome.isRecentKeyAction(PartyNoticeKind.seeked), isFalse,
          reason: 'la pillola è sparita da poco, ma è passato più di 1 s');
      expect(chrome.isRecentKeyAction(PartyNoticeKind.joined), isFalse);
      chrome.dispose();
    });
  });

  test('azione recente: un altro tasto in mezzo non cancella il salto', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController();
      chrome.seek(step, from: Duration.zero, duration: duration);
      async.elapse(const Duration(milliseconds: 300));
      chrome.showFeedback(const VolumeFeedback(volume: 70, muted: false));
      async.elapse(const Duration(milliseconds: 100));
      expect(chrome.isRecentKeyAction(PartyNoticeKind.seeked), isTrue,
          reason: '← e poi ↑: l\'avviso del salto di gruppo arriva dopo');

      chrome.showFeedback(const PlayFeedback(playing: false));
      expect(chrome.isRecentKeyAction(PartyNoticeKind.seeked), isTrue,
          reason: '← e poi Spazio');
      expect(chrome.isRecentKeyAction(PartyNoticeKind.paused), isTrue);
      expect(chrome.isRecentKeyAction(PartyNoticeKind.resumed), isFalse);
      chrome.dispose();
    });
  });

  test('azione recente: pausa e salto si ricordano separatamente', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController();
      chrome.showFeedback(const PlayFeedback(playing: false));
      async.elapse(const Duration(milliseconds: 200));
      chrome.seek(step, from: Duration.zero, duration: duration);
      expect(chrome.isRecentKeyAction(PartyNoticeKind.paused), isTrue);
      expect(chrome.isRecentKeyAction(PartyNoticeKind.seeked), isTrue);

      // L'ultimo Spazio decide tra pausa e ripresa.
      chrome.showFeedback(const PlayFeedback(playing: true));
      expect(chrome.isRecentKeyAction(PartyNoticeKind.paused), isFalse);
      expect(chrome.isRecentKeyAction(PartyNoticeKind.resumed), isTrue);

      async.elapse(const Duration(milliseconds: 1100));
      expect(chrome.isRecentKeyAction(PartyNoticeKind.paused), isFalse);
      expect(chrome.isRecentKeyAction(PartyNoticeKind.resumed), isFalse);
      expect(chrome.isRecentKeyAction(PartyNoticeKind.seeked), isFalse);
      chrome.dispose();
    });
  });

  test('in pausa, 8 s senza mouse né tasti: schermata di pausa', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController();
      var notified = 0;
      chrome.addListener(() => notified++);
      chrome.setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(PlayerChromeController.pauseScreenDelay -
          const Duration(milliseconds: 100));
      expect(chrome.pauseScreen, isFalse);
      async.elapse(const Duration(milliseconds: 100));
      expect(chrome.pauseScreen, isTrue);
      expect(chrome.controlsVisible, isFalse);
      expect(notified, 1);
      chrome.dispose();
    });
  });

  test('pausa: il mouse la chiude e riporta i controlli; il conto riparte',
      () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(PlayerChromeController.pauseScreenDelay);
      chrome.pointerActivity();
      expect(chrome.pauseScreen, isFalse);
      expect(chrome.controlsVisible, isTrue);
      async.elapse(PlayerChromeController.pauseScreenDelay);
      expect(chrome.pauseScreen, isTrue);
      chrome.dispose();
    });
  });

  test('pausa: un tasto la chiude senza mostrare i controlli', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(PlayerChromeController.pauseScreenDelay);
      chrome.keyActivity();
      expect(chrome.pauseScreen, isFalse);
      expect(chrome.controlsVisible, isFalse);
      async.elapse(const Duration(seconds: 4));
      chrome.keyActivity(); // il conto riparte dal tasto
      async.elapse(const Duration(seconds: 7));
      expect(chrome.pauseScreen, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(chrome.pauseScreen, isTrue);
      chrome.dispose();
    });
  });

  test('pausa non ammessa: niente schermata; se smette di esserlo si chiude',
      () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: false, canShowPauseScreen: false);
      async.elapse(const Duration(seconds: 20));
      expect(chrome.pauseScreen, isFalse);
      expect(chrome.controlsVisible, isTrue);

      chrome.setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(PlayerChromeController.pauseScreenDelay);
      expect(chrome.pauseScreen, isTrue);
      chrome.setPlayback(playing: false, canShowPauseScreen: false);
      expect(chrome.pauseScreen, isFalse);
      chrome.dispose();
    });
  });

  test('pausa: la ripresa la chiude', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(PlayerChromeController.pauseScreenDelay);
      chrome.setPlayback(playing: true, canShowPauseScreen: false);
      expect(chrome.pauseScreen, isFalse);
      chrome.dispose();
    });
  });

  test('pausa: con il pannello aperto non compare', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: false, canShowPauseScreen: true)
        ..togglePanel();
      async.elapse(const Duration(seconds: 20));
      expect(chrome.pauseScreen, isFalse);
      chrome.closePanel();
      async.elapse(PlayerChromeController.pauseScreenDelay);
      expect(chrome.pauseScreen, isTrue);
      chrome.togglePanel();
      expect(chrome.pauseScreen, isFalse, reason: 'aprire il pannello la chiude');
      chrome.dispose();
    });
  });

  test('stessi valori di nuovo: i conti non ripartono', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: true, canShowPauseScreen: false);
      async.elapse(const Duration(seconds: 2));
      chrome.setPlayback(playing: true, canShowPauseScreen: false);
      async.elapse(const Duration(seconds: 1));
      expect(chrome.controlsVisible, isFalse);
      chrome.dispose();
    });
  });

  test('post-play chiuso: resta chiuso, i controlli tornano', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: true, canShowPauseScreen: false);
      var notified = 0;
      chrome.addListener(() => notified++);
      // Durante il post-play i controlli sono nascosti.
      async.elapse(PlayerChromeController.hideDelay);
      expect(chrome.controlsVisible, isFalse);
      expect(notified, 1);
      expect(chrome.postPlayDismissed, isFalse);

      chrome.dismissPostPlay();
      expect(chrome.postPlayDismissed, isTrue);
      expect(chrome.controlsVisible, isTrue);
      expect(notified, 2);
      chrome.dismissPostPlay();
      expect(notified, 2, reason: 'già chiuso');

      // Il conto per nasconderli riparte dalla chiusura.
      async.elapse(
          PlayerChromeController.hideDelay - const Duration(milliseconds: 1));
      expect(chrome.controlsVisible, isTrue);
      async.elapse(const Duration(milliseconds: 1));
      expect(chrome.controlsVisible, isFalse);
      expect(notified, 3);
      expect(chrome.postPlayDismissed, isTrue);
      chrome.dispose();
    });
  });

  test('chat (spec E §9.6): i controlli si nascondono, la pausa non compare',
      () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: true, canShowPauseScreen: false);
      chrome.openPopup(PlayerPopup.chat);
      expect(chrome.chatOpen, isTrue);
      expect(chrome.panelOpen, isFalse);
      async.elapse(PlayerChromeController.hideDelay);
      expect(chrome.controlsVisible, isFalse,
          reason: 'la chat non tiene su i controlli');
      chrome.setPlayback(playing: false, canShowPauseScreen: true);
      async.elapse(const Duration(seconds: 20));
      expect(chrome.pauseScreen, isFalse);
      chrome.closePopup(PlayerPopup.chat);
      async.elapse(PlayerChromeController.pauseScreenDelay);
      expect(chrome.pauseScreen, isTrue);
      chrome.openPopup(PlayerPopup.chat);
      expect(chrome.pauseScreen, isFalse, reason: 'aprire la chat la chiude');
      chrome.dispose();
    });
  });

  test('un riquadro alla volta: tracce e chat si sostituiscono', () {
    final chrome = PlayerChromeController();
    var notified = 0;
    chrome.addListener(() => notified++);
    chrome.openPopup(PlayerPopup.chat);
    chrome.togglePanel();
    expect(chrome.popup, PlayerPopup.tracks);
    expect(chrome.chatOpen, isFalse);
    chrome.closePopup(PlayerPopup.chat);
    expect(chrome.panelOpen, isTrue,
        reason: 'chiude solo il riquadro indicato');
    chrome.closePopup();
    expect(chrome.popup, isNull);
    chrome.togglePopup(PlayerPopup.chat);
    chrome.togglePopup(PlayerPopup.chat);
    expect(chrome.popup, isNull);
    expect(notified, 5);
    chrome.dispose();
  });

  test('dispose: nessun timer in sospeso', () {
    fakeAsync((async) {
      final chrome = PlayerChromeController()
        ..setPlayback(playing: true, canShowPauseScreen: false);
      chrome.showFeedback(const PlayFeedback(playing: true));
      chrome.setPlayback(playing: false, canShowPauseScreen: true);
      chrome.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });
}
