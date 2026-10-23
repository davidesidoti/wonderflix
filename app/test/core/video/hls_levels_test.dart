import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/video/hls_levels.dart';

void main() {
  const copy = 'main.m3u8?VideoCodec=hevc,h264&ApiKey=x';
  const transcode = 'main.m3u8?VideoCodec=h264&AllowVideoStreamCopy=false';

  test('sceglie il livello che copia il video, anche se non è il primo', () {
    expect(copyLevel([transcode, copy]), 1);
    expect(copyLevel([copy, transcode]), 0);
  });

  test('senza livelli in copia, il primo', () {
    expect(copyLevel([transcode]), 0);
    expect(copyLevel([]), 0);
  });
}
