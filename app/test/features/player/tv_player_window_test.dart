import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/player/tv_player_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'niente schermo intero da gestire: la TV è già a tutto schermo',
    () async {
      final window = TvPlayerWindow();
      expect(window.supportsFullScreen, isFalse);
      expect(await window.isFullScreen(), isTrue);
      await window.setFullScreen(false);
      await window.lockLandscape();
      await window.unlockOrientation();
      await window.setPreventClose(true);
      await window.setPreventClose(false);
      await window.hide();
      var emitted = false;
      final sub = window.fullScreenChanges.listen((_) => emitted = true);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(emitted, isFalse);
    },
  );

  test(
    'gli ascoltatori di chiusura si aggiungono e si tolgono senza errori',
    () {
      final window = TvPlayerWindow();
      Future<void> onClose() async {}
      window.addCloseListener(onClose);
      window.removeCloseListener(onClose);
    },
  );

  test('destroy chiude l\'app con SystemNavigator.pop', () async {
    final calls = <String>[];
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await TvPlayerWindow().destroy();
    expect(calls, contains('SystemNavigator.pop'));
  });
}
