import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/network_target_policy.dart';

void main() {
  test(
    'only network media URLs without credentials or controls are accepted',
    () {
      for (final text in [
        'file:///etc/passwd',
        'javascript:alert(1)',
        'data:text/html,hello',
        'concat:https://example.com/a|file:///secret',
        'https://user:pass@example.com/',
        'https://example.com/%0d%0aHost:localhost',
        'https:///missing',
      ]) {
        expect(
          () => NetworkTargetPolicy.validateUri(Uri.parse(text)),
          throwsFormatException,
        );
      }
      NetworkTargetPolicy.validateUri(
        Uri.parse('https://example.com/video.m3u8'),
      );
    },
  );

  test('private address forms cannot evade the destination policy', () {
    for (final address in [
      '0.0.0.0',
      '127.0.0.1',
      '10.0.0.1',
      '172.16.0.1',
      '192.168.1.1',
      '169.254.169.254',
      '100.64.0.1',
      '224.0.0.1',
      '::1',
      'fc00::1',
      'fe80::1',
      '::ffff:127.0.0.1',
      '::ffff:192.168.1.1',
      '2002:7f00:1::',
    ]) {
      expect(
        NetworkTargetPolicy.isPrivate(InternetAddress(address)),
        isTrue,
        reason: address,
      );
    }
    expect(NetworkTargetPolicy.isPrivate(InternetAddress('8.8.8.8')), isFalse);
    expect(
      NetworkTargetPolicy.isPrivate(InternetAddress('2606:4700:4700::1111')),
      isFalse,
    );
  });

  test(
    'production transport blocks loopback before a request reaches it',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) {
        requests++;
        request.response.close();
      });
      final client = MediaHttpClient();
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      for (final host in ['127.0.0.1', 'localhost']) {
        await expectLater(
          client.open(
            Uri.parse('http://$host:${server.port}/'),
            policy: HeaderPolicy({}),
          ),
          throwsFormatException,
        );
      }
      expect(requests, 0);
    },
  );

  test('headers cannot override routing or inject additional requests', () {
    final uri = Uri.parse('https://media.test/');
    final policy = HeaderPolicy({
      uri: {
        'Host': '127.0.0.1',
        'Connection': 'upgrade',
        'Transfer-Encoding': 'chunked',
        'X-Evil': 'value\r\nInjected: yes',
        'Authorization': 'Bearer legitimate',
        'Referer': 'https://media.test/',
      },
    });
    expect(policy.forUri(uri), {
      'Authorization': 'Bearer legitimate',
      'Referer': 'https://media.test/',
    });
    expect(policy.forUri(Uri.parse('https://other.test/')), isEmpty);
  });
}
