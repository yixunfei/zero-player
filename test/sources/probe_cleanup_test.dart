import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/sources/application/source_probe.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/features/sources/domain/source_probe_result.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test('only explicit failure kinds are cleanup candidates', () {
    for (final status in [404, 410, 403]) {
      expect(
        classifyProbeFailure(
          RemoteFailure(FailureKind.http, 'HTTP', status: status),
        ),
        SourceProbeState.unavailable,
      );
    }
    for (final status in [408, 429, 500, 503]) {
      expect(
        classifyProbeFailure(
          RemoteFailure(FailureKind.http, 'HTTP', status: status),
        ),
        SourceProbeState.inconclusive,
      );
    }
    expect(
      classifyProbeFailure(
        const RemoteFailure(FailureKind.cancelled, 'cancel'),
      ),
      SourceProbeState.cancelled,
    );
    expect(
      classifyProbeFailure(const RemoteFailure(FailureKind.timeout, 'timeout')),
      SourceProbeState.inconclusive,
    );
    expect(
      classifyProbeFailure(const RemoteFailure(FailureKind.network, 'network')),
      SourceProbeState.inconclusive,
    );
  });
  test('batch cleanup excludes healthy, busy and unprobed sources', () async {
    final db = AppDatabase.memory();
    final http = MediaHttpClient(allowPrivateNetworks: true);
    final repository = SourceRepository(db);
    final probe = SourceProbe(repository, DocumentClient(http));
    final server = await HttpTestServer.start((request) {
      if (request.uri.path == '/ok') {
        request.response.write('{"list":[]}');
      } else {
        request.response.statusCode = request.uri.path == '/busy' ? 503 : 404;
      }
    });
    addTearDown(() async {
      probe.dispose();
      http.close();
      await server.close();
      await db.close();
    });
    final ok = await repository.saveManual('ok', server.baseUri.resolve('ok'));
    final gone = await repository.saveManual(
      'gone',
      server.baseUri.resolve('gone'),
    );
    final busy = await repository.saveManual(
      'busy',
      server.baseUri.resolve('busy'),
    );
    final untouched = await repository.saveManual(
      'untouched',
      server.baseUri.resolve('untouched'),
    );
    await probe.run(
      (await repository.all()).where((s) => s.id != untouched).toList(),
    );
    expect(probe.unavailable, {gone});
    expect(probe.results[ok], SourceProbeState.available);
    expect(probe.results[busy], SourceProbeState.inconclusive);
    await repository.batch(
      probe.unavailable.toList(),
      enabled: false,
      suppressed: true,
    );
    expect((await repository.all()).map((s) => s.id).toSet(), {
      ok,
      busy,
      untouched,
    });
    expect((await repository.find(busy))!.failures, 0);
    expect((await repository.find(untouched))!.checkedAt, isNull);
  });
}
