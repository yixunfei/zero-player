import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/hls/hls_manifest.dart';

void main() {
  final base = Uri.parse('https://source.test/path/list.m3u8?token=abc');
  test(
    'preserves durations, discontinuity and relative URI after redirect',
    () {
      final manifest = HlsManifest.parse('''#EXTM3U
#EXT-X-MEDIA-SEQUENCE:42
#EXTINF:2.5,
one.ts?token=1
#EXT-X-DISCONTINUITY
#EXT-X-BYTERANGE:32@16
#EXTINF:1.25,
../two.ts
#EXT-X-ENDLIST
''', base);
      expect(manifest.duration, const Duration(milliseconds: 3750));
      expect(manifest.segments[0].sequence, 42);
      expect(manifest.segments[1].sequence, 43);
      expect(manifest.segments[1].byteRange, '32@16');
      expect(manifest.segments[1].discontinuity, isTrue);
      expect(manifest.segments[1].start, const Duration(milliseconds: 2500));
      expect(manifest.isComplete, isTrue);
      expect(manifest.segments[1].uri.toString(), 'https://source.test/two.ts');
    },
  );

  test('rewrites KEY MAP MEDIA and variants without editing unknown tags', () {
    final manifest = HlsManifest.parse('''#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,NAME="English, original",URI="audio?id=1"
#EXT-X-KEY:METHOD=AES-128,URI="key.bin"
#EXT-X-MAP:URI="init.mp4",BYTERANGE="100@0"
#EXT-X-STREAM-INF:BANDWIDTH=123
variant?id=2
#VENDOR-NOTE:URI="do-not-touch"
''', base);
    final output = manifest.rewrite(
      (uri) => Uri.parse(
        'http://127.0.0.1:1234/token/${Uri.encodeComponent(uri.toString())}',
      ),
    );
    expect(manifest.isMaster, isTrue);
    expect(manifest.playlistUris.length, 2);
    expect(output, contains('NAME="English, original"'));
    expect(output, contains('BYTERANGE="100@0"'));
    expect(output, contains('#VENDOR-NOTE:URI="do-not-touch"'));
    expect(output.split('http://127.0.0.1:1234/').length - 1, 4);
  });

  test('rejects HTML, invalid durations and unsafe resource schemes', () {
    expect(
      () => HlsManifest.parse('<html>captcha</html>', base),
      throwsFormatException,
    );
    expect(
      () => HlsManifest.parse('#EXTM3U\n#EXTINF:NaN,\na.ts', base),
      throwsFormatException,
    );
    expect(
      () => HlsManifest.parse('#EXTM3U\n#EXTINF:1,\nfile:///secret', base),
      throwsFormatException,
    );
  });
}
