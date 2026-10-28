import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/catalog/data/cms_provider.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test('CMS credentials are bound to the endpoint origin', () async {
    final http = MediaHttpClient(allowPrivateNetworks: true);
    addTearDown(http.close);
    final endpoint = Uri.parse('https://source.test/api');
    final provider = CmsProvider(
      VideoSource(
        id: 's',
        name: 's',
        endpoint: endpoint,
        headers: const {
          'Authorization': 'secret',
          'Cookie': 'private',
          'X-Api-Key': 'key',
        },
      ),
      DocumentClient(http),
    );
    expect(
      (await provider.resolve(
        Episode('same', endpoint.resolve('/video.mp4')),
      )).headers['Authorization'],
      'secret',
    );
    expect(
      (await provider.resolve(
        Episode('other', Uri.parse('https://cdn.test/video.mp4')),
      )).headers,
      isEmpty,
    );
    expect(
      (await provider.resolve(
        Episode('downgrade', Uri.parse('http://source.test/video.mp4')),
      )).headers,
      isEmpty,
    );
  });

  test(
    'If-Range is supplied to the initial origin but never leaked through redirects',
    () async {
      String? atSource;
      String? atTarget;
      final target = await HttpTestServer.start((request) {
        atTarget = request.headers.value('if-range');
        request.response.write('body');
      });
      final source = await HttpTestServer.start((request) {
        atSource = request.headers.value('if-range');
        request.response.statusCode = 302;
        request.response.headers.set('location', target.baseUri.toString());
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      addTearDown(http.close);
      addTearDown(source.close);
      addTearDown(target.close);
      final payload = await http.open(
        source.baseUri,
        policy: HeaderPolicy({}),
        range: 'bytes=2-',
        ifRange: '"version-one"',
      );
      await payload.body.drain<void>();
      expect(atSource, '"version-one"');
      expect(atTarget, isNull);
    },
  );
}
