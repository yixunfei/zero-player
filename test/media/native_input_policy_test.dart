import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/engine/native_input_policy.dart';

void main() {
  test(
    'native decoders reject direct URLs and unregistered local services',
    () {
      for (final uri in [
        'https://media.test/video.mp4',
        'http://192.168.1.1/video.mp4',
        'http://127.0.0.1:1234/admin',
        'file:///C:/secret',
        'javascript:alert(1)',
      ]) {
        expect(
          () => validateNativeInput(Uri.parse(uri), registered: false),
          throwsFormatException,
        );
      }
      validateNativeInput(
        Uri.parse('http://127.0.0.1:1234/token/1'),
        registered: true,
      );
      for (final uri in [
        'https://media.test/video.mp4',
        'http://127.0.0.1:1234/token/1?url=remote',
        'http://127.0.0.1:1234/token/1#unsafe',
      ]) {
        expect(
          () => validateNativeInput(Uri.parse(uri), registered: true),
          throwsFormatException,
        );
      }
    },
  );
}
