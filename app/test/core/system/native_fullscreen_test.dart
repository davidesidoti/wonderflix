import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/system/native_fullscreen.dart';

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

  test('entra ed esce con il codice nativo di media_kit', () async {
    final fullScreen = NativeFullScreen();
    expect(fullScreen.active, isFalse);

    await fullScreen.enter();
    expect(fullScreen.active, isTrue);
    expect(calls, ['Utils.EnterNativeFullscreen']);

    await fullScreen.exit();
    expect(fullScreen.active, isFalse);
    expect(calls, ['Utils.EnterNativeFullscreen', 'Utils.ExitNativeFullscreen']);
  });

  test('richieste ripetute arrivano una volta sola', () async {
    final fullScreen = NativeFullScreen();
    await fullScreen.enter();
    await fullScreen.enter();
    await fullScreen.exit();
    await fullScreen.exit();
    expect(calls, ['Utils.EnterNativeFullscreen', 'Utils.ExitNativeFullscreen']);
  });

  test('uscire senza essere entrati non chiama nulla', () async {
    final fullScreen = NativeFullScreen();
    await fullScreen.exit();
    expect(fullScreen.active, isFalse);
    expect(calls, isEmpty);
  });

  test('due ingressi ravvicinati: una sola chiamata', () async {
    final fullScreen = NativeFullScreen();
    await Future.wait([fullScreen.enter(), fullScreen.enter()]);
    expect(calls, ['Utils.EnterNativeFullscreen']);
  });
}
