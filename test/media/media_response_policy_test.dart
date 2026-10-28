import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/network/media_response_policy.dart';

void main() {
  test('document and executable MIME types are rejected', () {
    for (final type in [
      'text/html',
      'application/javascript',
      'application/json',
      'image/svg+xml',
      'application/x-msdownload',
    ]) {
      expect(() => validateMediaType(type), throwsFormatException);
    }
    validateMediaType('video/mp4');
    validateMediaType('application/octet-stream');
  });
  test(
    'split payloads cannot smuggle markup, executables or playlists',
    () async {
      for (final value in [
        '<!DOCTYPE html><script>evil</script>',
        '#EXTM3U\nfile:///secret',
        '[playlist]\nFile1=file:///secret',
        'MZexecutable',
        '#!/bin/sh',
        'ffconcat version 1.0',
      ]) {
        final bytes = utf8.encode(value);
        await expectLater(
          guardMediaBody(
            Stream.fromIterable([
              bytes.take(1).toList(),
              bytes.skip(1).toList(),
            ]),
          ).toList(),
          throwsFormatException,
        );
      }
    },
  );
  test('binary payload is preserved byte for byte', () async {
    final bytes = List.generate(1800, (i) => i % 256);
    final output = await guardMediaBody(
      Stream.fromIterable([
        bytes.sublist(0, 8),
        bytes.sublist(8, 600),
        bytes.sublist(600),
      ]),
    ).expand((chunk) => chunk).toList();
    expect(output, bytes);
  });
}
