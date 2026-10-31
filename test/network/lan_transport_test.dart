import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/lan_access_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';

void main() {
  test(
    'production transport enforces LAN grants, redirects and revocation',
    () async {
      final addresses = (await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )).expand((interface) => interface.addresses).where(isLanAddress);
      if (addresses.isEmpty) {
        markTestSkipped(
          'No RFC1918 interface available for a real LAN transport fixture',
        );
        return;
      }
      final server = await HttpServer.bind(addresses.first, 0);
      final other = await HttpServer.bind(addresses.first, 0);
      final origin = Uri.parse(
        'http://${addresses.first.address}:${server.port}',
      );
      final alternate = origin.replace(port: other.port);
      var requests = 0, otherRequests = 0;
      var approved = false;
      server.listen((request) async {
        requests++;
        if (request.uri.path == '/redirect') {
          request.response.statusCode = 302;
          request.response.headers.set('location', alternate.toString());
        } else {
          request.response.write('media');
        }
        await request.response.close();
      });
      other.listen((request) async {
        otherRequests++;
        await request.response.close();
      });
      final client = MediaHttpClient(
        allowLanOrigin: (uri) =>
            approved && {origin.origin, alternate.origin}.contains(uri.origin),
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
        await other.close(force: true);
      });
      final scope = HeaderPolicy({origin: {}});
      await expectLater(
        client.open(origin, policy: scope),
        throwsFormatException,
      );
      expect(requests, 0);
      approved = true;
      final allowed = await client.open(origin, policy: scope);
      expect(
        await allowed.body.expand((bytes) => bytes).toList(),
        'media'.codeUnits,
      );
      await expectLater(
        client.open(origin.resolve('/redirect'), policy: scope),
        throwsFormatException,
      );
      expect(otherRequests, 0);
      await expectLater(
        client.open(
          origin,
          policy: HeaderPolicy({Uri.parse('https://public.test'): {}}),
        ),
        throwsFormatException,
      );
      approved = false;
      client.resetConnections();
      await expectLater(
        client.open(origin, policy: scope),
        throwsFormatException,
      );
      expect(requests, 2);
    },
  );
}
