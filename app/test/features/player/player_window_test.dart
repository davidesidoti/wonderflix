import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/system/native_fullscreen.dart';
import 'package:wonderflix/features/player/player_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.alexmercerind/media_kit_video');
  late List<String> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('schermo intero con il codice nativo di media_kit', () async {
    final fullScreen = NativeFullScreen();
    final window = WindowManagerPlayerWindow(fullScreen: fullScreen);

    await window.setFullScreen(true);
    expect(await window.isFullScreen(), isTrue);
    expect(fullScreen.active, isTrue);

    await window.setFullScreen(false);
    expect(await window.isFullScreen(), isFalse);
    expect(calls, ['Utils.EnterNativeFullscreen', 'Utils.ExitNativeFullscreen']);
  });

  test('senza argomenti usa lo stato condiviso', () async {
    final window = WindowManagerPlayerWindow();
    // Lo stato è condiviso: se un'attesa fallisce a metà non resta acceso.
    addTearDown(nativeFullScreen.exit);
    await window.setFullScreen(true);
    expect(nativeFullScreen.active, isTrue);
    await window.setFullScreen(false);
    expect(nativeFullScreen.active, isFalse);
  });
}
