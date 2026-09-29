import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/device_profile.dart';

void main() {
  test('direct play di tutto, transcodifica HLS di ripiego, sottotitoli', () {
    final profile = buildDeviceProfile(maxBitrate: 8000000);
    expect(profile['MaxStreamingBitrate'], 8000000);
    expect(profile['MaxStaticBitrate'], 8000000);
    expect(profile['DirectPlayProfiles'], [
      {'Type': 'Video'},
      {'Type': 'Audio'},
    ]);

    final transcoding =
        (profile['TranscodingProfiles'] as List).single as Map<String, dynamic>;
    expect(transcoding['Protocol'], 'hls');
    expect(transcoding['Container'], 'ts');
    expect(transcoding['VideoCodec'], 'h264');

    final subtitles =
        (profile['SubtitleProfiles'] as List).cast<Map<String, dynamic>>();
    Set<String> formats(String method) => {
          for (final s in subtitles)
            if (s['Method'] == method) s['Format'] as String,
        };
    expect(formats('External'), containsAll(['srt', 'ass', 'ssa', 'vtt', 'sub']));
    expect(formats('External'), isNot(contains('pgssub')));
    expect(formats('Embed'), containsAll(['srt', 'ass', 'pgssub', 'dvdsub']));
  });

  test('qualità originale: nessun limite pratico', () {
    expect(buildDeviceProfile()['MaxStreamingBitrate'], originalQualityBitrate);
  });
}
