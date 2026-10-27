import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/sources/application/source_probe.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'probe records measured API latency and verified metadata, and restarts',
    () async {
      final db = AppDatabase.memory();
      final repository = SourceRepository(db);
      final http = MediaHttpClient();
      final probe = SourceProbe(repository, DocumentClient(http));
      final server = await HttpTestServer.start((request) async {
        request.response.write(
          jsonEncode({
            'list': [],
            'site_name': '测试主站',
            'site_url': 'https://main.test',
          }),
        );
      });
      try {
        final id = await repository.saveManual('127.0.0.1', server.baseUri);
        await probe.run(await repository.all());
        final source = (await repository.find(id))!;
        expect(source.apiOk, isTrue);
        expect(source.latencyMs, greaterThanOrEqualTo(0));
        expect(source.checkedAt, isNotNull);
        expect(source.displayName, '测试主站');
        expect(source.homepage!.host, 'main.test');
        probe.cancel();
        await probe.run(await repository.all());
        expect(server.calls['/'], 2);
      } finally {
        probe.dispose();
        http.close();
        await server.close();
        await db.close();
      }
    },
  );
}
