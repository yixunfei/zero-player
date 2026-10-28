import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/hls/hls_manifest.dart';

void main() {
  final base = Uri.parse('https://media.test/index.m3u8');
  test(
    'unquoted or unrecognized HLS resource attributes cannot bypass rewriting',
    () {
      for (final tag in [
        '#EXT-X-KEY:METHOD=AES-128,URI=https://other.test/key',
        '#EXT-X-MAP:uri="https://other.test/init.mp4"',
        '#EXT-X-CONTENT-STEERING:SERVER-URI="https://other.test/redirect"',
      ]) {
        final manifest = HlsManifest.parse('#EXTM3U\n$tag', base);
        expect(() => manifest.rewrite((uri) => uri), throwsFormatException);
      }
    },
  );
}
