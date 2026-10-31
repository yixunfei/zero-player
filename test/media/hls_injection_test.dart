import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/hls/hls_manifest.dart';
import 'package:zero_player/media/hls/offline_rewriter.dart';

void main() {
  final base = Uri.parse('https://media.test/index.m3u8');
  test('query variables cannot inject lines or URI attributes', () {
    for (final value in [
      'safe\nhttp://127.0.0.1/admin',
      'safe",URI="http://127.0.0.1/admin',
      'safe\r#EXT-X-KEY:METHOD=AES-128,URI="http://evil.test/key"',
      'safe\u0000.ts',
    ]) {
      expect(
        () => HlsManifest.parse(
          '#EXTM3U\n#EXT-X-DEFINE:QUERYPARAM="v"\n#EXTINF:1,\n{\$v}.ts',
          base.replace(queryParameters: {'v': value}),
        ),
        throwsFormatException,
      );
    }
  });

  test('recursive definitions and expanded lines are bounded', () {
    final seed = 'a' * 8192;
    expect(
      () => HlsManifest.parse(
        '#EXTM3U\n#EXT-X-DEFINE:NAME="v",VALUE="$seed"\n'
        r'#EXT-X-DEFINE:NAME="w",VALUE="{$v}{$v}"',
        base,
      ),
      throwsFormatException,
    );
    expect(
      () => HlsManifest.parse(
        '#EXTM3U\n#EXT-X-DEFINE:NAME="v",VALUE="$seed"\n${r'{$v}' * 9}.ts',
        base,
      ),
      throwsFormatException,
    );
  });

  test(
    'offline pipeline rejects malformed references before fetching resources',
    () async {
      for (final line in [
        '#EXT-X-KEY:METHOD=AES-128,URI=http://evil.test/key',
        '#EXT-X-KEY:METHOD=AES-128,URI="key",URI="http://evil.test/key"',
        '#EXT-X-CONTENT-STEERING:SERVER-URI="http://evil.test/steer"',
        '#EXT-X-MAP:URI="file:///C:/secret"',
        '#EXT-X-MAP:URI="http://media.test/%0d%0aInjected"',
      ]) {
        var downloads = 0;
        await expectLater(
          Future(() async {
            final manifest = HlsManifest.parse(
              '#EXTM3U\n$line\n#EXTINF:1,\na.ts',
              base,
            );
            await rewriteOffline(manifest, (
              uri, {
              range,
              playlist = false,
            }) async {
              downloads++;
              return uri;
            });
          }),
          throwsFormatException,
        );
        expect(downloads, 0);
      }
    },
  );
}
