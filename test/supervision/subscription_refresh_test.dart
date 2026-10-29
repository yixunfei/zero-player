import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/sources/application/subscription_service.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';
import '../../test_support/http_test_server.dart';
import '../../test_support/supervision_fixture.dart';

void main() {
  test(
    'supervised refresh updates approved lists without adding live sources',
    () async {
      final f = SupervisionFixture();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      late String catalog;
      final requested = <String>[];
      final server = await HttpTestServer.start((request) {
        requested.add(request.uri.path);
        request.response.write(
          request.uri.path == '/catalog'
              ? catalog
              : '#EXTM3U\n#EXTINF:-1,新闻\nhttps://example.org/live.mp4\n',
        );
      });
      final network = DocumentClient(http);
      final live = LiveRepository(
        f.db,
        network,
        policy: f.policy,
        authorize: () => f.guard.require(SensitiveOperation.channels),
        canEnable: () => f.guard.allows(SensitiveOperation.channels),
      );
      final service = SubscriptionService(network, f.sources, live: live);
      try {
        await f.load();
        final url = server.baseUri.resolve('/catalog');
        String data(List<String> paths) => jsonEncode({
          'lives': [
            for (final path in paths)
              {'name': path, 'url': server.baseUri.resolve(path).toString()},
          ],
        });
        catalog = data(['/approved']);
        await service.import(await service.preview(url), 'catalog');
        final approved = (await live.lists()).single['id'] as String;
        await live.setListEnabled(approved, false);
        await f.configure();
        catalog = data(['/approved', '/unapproved']);
        requested.clear();
        await service.refresh((await f.sources.subscriptions()).single);
        expect(requested, contains('/approved'));
        expect(requested, isNot(contains('/unapproved')));
        expect(await live.lists(), hasLength(1));
        expect((await live.lists()).single['enabled'], 0);
        await f.authorized(SensitiveOperation.channels, () async {
          await service.import(await service.preview(url), 'catalog');
        });
        expect(await live.lists(), hasLength(2));
      } finally {
        await service.close();
        http.close();
        await server.close();
        await f.close();
      }
    },
  );
}
