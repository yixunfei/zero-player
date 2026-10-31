import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/sources/application/source_connectivity.dart';
import 'package:zero_player/features/sources/application/source_probe.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/features/sources/domain/source_probe_result.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'foreground channel probes reach eight independent APIs concurrently',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final repository = SourceRepository(db);
      final probe = SourceProbe(
        repository,
        DocumentClient(http),
        connectivity: _Connected(),
      );
      final release = Completer<void>();
      final ready = Completer<void>();
      final servers = <HttpTestServer>[];
      var started = 0;
      Future<void>? run;
      addTearDown(() async {
        release.isCompleted ? null : release.complete();
        probe.cancel();
        await run;
        probe.dispose();
        http.close();
        for (final server in servers) {
          await server.close();
        }
        await db.close();
      });
      for (var i = 0; i < 8; i++) {
        final server = await HttpTestServer.start((request) async {
          if (++started == 8) ready.complete();
          await release.future;
          request.response.write('{"list":[],"info":{"site_name":"fixture"}}');
        });
        servers.add(server);
        await repository.saveManual('channel$i', server.baseUri.resolve('api'));
      }
      run = probe.run(await repository.all());
      await ready.future.timeout(const Duration(seconds: 8));
      expect(
        started,
        8,
        reason: 'must not be capped at two, six, or background budget four',
      );
      release.complete();
      await run;
      expect(probe.results.values, everyElement(SourceProbeState.available));
      expect(probe.results.length, 8);
    },
  );
}

class _Connected implements SourceConnectivity {
  @override
  Future<SourceConnection> inspect(Uri uri, CancellationToken token) async =>
      const SourceConnection();
}
