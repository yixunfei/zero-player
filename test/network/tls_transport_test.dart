import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';

void main() {
  test('HTTPS sends a TLS handshake, never plaintext HTTP', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final client = MediaHttpClient(allowPrivateNetworks: true);
    addTearDown(() async {
      client.close();
      await server.close();
    });
    final firstByte = server.first.then((socket) async {
      try {
        return (await socket.first).first;
      } finally {
        socket.destroy();
      }
    });
    await expectLater(
      client.open(
        Uri.parse('https://127.0.0.1:${server.port}/'),
        policy: HeaderPolicy({}),
      ),
      throwsA(isA<HandshakeException>()),
    );
    expect(await firstByte, 0x16);
  });
}
