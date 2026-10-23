import 'media_kit_engine.dart';
import 'video_engine.dart';

VideoEngine createVideoEngine({required bool hardwareDecoding}) =>
    MediaKitEngine(hwdec: hardwareDecoding ? 'auto-safe' : 'no');
