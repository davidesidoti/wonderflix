import 'video_engine.dart';
import 'web_video_engine.dart';

// Nel browser la decodifica la sceglie lui: [hardwareDecoding] non serve.
VideoEngine createVideoEngine({required bool hardwareDecoding}) =>
    WebVideoEngine();
