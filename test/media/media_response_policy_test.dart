import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/network/media_response_policy.dart';

void main() {
  test('forged Content-Range cannot disable entity prefix validation', () {
    expect(startsMediaEntity('bytes 1-512/513'), isTrue);
    expect(
      startsMediaEntity('bytes 1-512/513', requestedRange: 'bytes=0-'),
      isTrue,
    );
    expect(startsMediaEntity('invalid', requestedRange: 'bytes=20-'), isTrue);
    expect(
      startsMediaEntity('bytes 20-512/513', requestedRange: 'bytes=20-'),
      isFalse,
    );
    expect(
      startsMediaEntity('bytes 20-512/513', requestedRange: 'bytes=-493'),
      isFalse,
    );
  });
  test('inconsistent ranges cannot bypass prefix inspection', () {
    for (final pair in [
      ['bytes 1-64/100', 'bytes=-64'],
      ['bytes 36-98/100', 'bytes=-64'],
      ['bytes 36-99/*', 'bytes=-64'],
      ['bytes 20-10/100', 'bytes=20-'],
      ['bytes 20-100/100', 'bytes=20-'],
      ['bytes 20-60/100', 'bytes=20-40'],
      ['bytes 1-99/100', 'bytes=-200'],
    ]) {
      expect(
        startsMediaEntity(pair[0], requestedRange: pair[1]),
        isTrue,
        reason: '$pair',
      );
    }
    expect(
      startsMediaEntity('bytes 36-99/100', requestedRange: 'bytes=-64'),
      isFalse,
    );
    expect(
      startsMediaEntity('bytes 20-40/100', requestedRange: 'bytes=20-40'),
      isFalse,
    );
  });
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
