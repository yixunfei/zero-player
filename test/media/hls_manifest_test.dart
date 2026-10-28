import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/hls/hls_manifest.dart';

void main() {
  final base = Uri.parse('https://source.test/path/list.m3u8?token=abc');
  _regressionTests(base);
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

void _regressionTests(Uri base) {
  test(
    'zero duration consumes its range and discontinuity without leaking state',
    () {
      final manifest = HlsManifest.parse('''#EXTM3U
#EXT-X-MEDIA-SEQUENCE:7
#EXT-X-DISCONTINUITY
#EXT-X-BYTERANGE:2@0
#EXTINF:0,
empty.ts
#EXTINF:2,
next.ts
#EXT-X-ENDLIST
''', base);
      expect(manifest.segments, hasLength(2));
      expect(manifest.segments.first.duration, Duration.zero);
      expect(manifest.segments.last.sequence, 8);
      expect(manifest.segments.last.byteRange, isNull);
      expect(manifest.segments.last.discontinuity, isFalse);
    },
  );

  test(
    'key URI whitespace is preserved and inline or DRM keys are not proxied',
    () {
      final manifest = HlsManifest.parse('''#EXTM3U
#EXT-X-KEY:METHOD=AES-128, URI="data:application/octet-stream;base64,AA=="
#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES, URI="skd://license"
#EXT-X-MAP: URI="init.mp4"
#EXTINF:2,
a.ts
#EXT-X-ENDLIST
''', base);
      final requested = <Uri>[];
      final rewritten = manifest.rewrite((uri) {
        requested.add(uri);
        return Uri.parse('http://localhost/proxy');
      });
      expect(rewritten, contains(', URI="data:'));
      expect(rewritten, contains(', URI="skd:'));
      expect(rewritten, contains(': URI="http://localhost/proxy"'));
      expect(requested.map((uri) => uri.scheme), everyElement('https'));
      expect(requested, hasLength(2));
    },
  );

  test(
    'variables expand across declared parent imports and reject unknown values',
    () {
      final parent = HlsManifest.parse(r'''#EXTM3U
#EXT-X-DEFINE:NAME="token",VALUE="signed-value"
#EXT-X-STREAM-INF:BANDWIDTH=100
child.m3u8?token={$token}
''', base);
      expect(
        parent.playlistUris.single.queryParameters['token'],
        'signed-value',
      );
      final child = HlsManifest.parse(
        r'''#EXTM3U
#EXT-X-DEFINE:IMPORT="token"
#EXTINF:2,
part.ts?auth={$token}
#EXT-X-ENDLIST
''',
        base,
        variables: parent.variables,
      );
      expect(child.segments.single.uri.queryParameters['auth'], 'signed-value');
      expect(child.rewrite((uri) => uri), isNot(contains(r'{$token}')));
      expect(
        () => HlsManifest.parse(
          r'#EXTM3U'
          '\n'
          r'{$missing}.ts',
          base,
        ),
        throwsFormatException,
      );
    },
  );
}
