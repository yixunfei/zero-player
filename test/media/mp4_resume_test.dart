import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/downloads/application/mp4_download.dart';
import '../../test_support/http_test_server.dart';

void main() {
  _completionTests();
  _restartTests();
  _checkpointFailureTest();
}

void _checkpointFailureTest() {
  test(
    'a failed truncation never attaches a new validator to old bytes',
    () async {
      late _Fixture fixture;
      fixture = await _Fixture.create((request) async {
        final part = File('${fixture.directory.path}/video.mp4.part');
        await part.delete();
        await Directory(part.path).create();
        request.response.headers.set('etag', 'version-b');
        request.response.contentLength = 4;
        request.response.add([5, 6, 7, 8]);
      });
      await fixture.seed([1, 2]);
      await expectLater(fixture.run(), throwsA(isA<FileSystemException>()));
      final state =
          jsonDecode(
                await File(
                  '${fixture.directory.path}/mp4-state.json',
                ).readAsString(),
              )
              as Map;
      expect(state['etag'], 'version-a');
      expect(fixture.validated, 0);
    },
  );
}

void _completionTests() {
  test(
    'complete part receiving 416 is validated and finalized without redownload',
    () async {
      final fixture = await _Fixture.create((request) {
        expect(request.headers.value('range'), 'bytes=4-');
        expect(request.headers.value('if-range'), 'version-a');
        request.response.statusCode = 416;
        request.response.headers.set('content-range', 'bytes */4');
        request.response.headers.set('etag', 'version-a');
      });
      await fixture.seed([1, 2, 3, 4]);
      await fixture.run();
      expect(await fixture.output.readAsBytes(), [1, 2, 3, 4]);
      expect(fixture.validated, 1);
      expect(fixture.progress, [4, 4, 4]);
      expect(fixture.server.calls['/video.mp4'], 1);
    },
  );
  test(
    'partial part uses conditional range and appends only the matching version',
    () async {
      final fixture = await _Fixture.create((request) {
        expect(request.headers.value('range'), 'bytes=2-');
        expect(request.headers.value('if-range'), 'version-a');
        request.response.statusCode = 206;
        request.response.contentLength = 2;
        request.response.headers.set('content-range', 'bytes 2-3/4');
        request.response.headers.set('etag', 'version-a');
        request.response.add([3, 4]);
      });
      await fixture.seed([1, 2]);
      await fixture.run();
      expect(await fixture.output.readAsBytes(), [1, 2, 3, 4]);
    },
  );
}

void _restartTests() {
  test(
    'unsatisfied range with changed length restarts once from zero',
    () async {
      final fixture = await _Fixture.create((request) {
        if (request.headers.value('range') != null) {
          request.response.statusCode = 416;
          request.response.headers.set('content-range', 'bytes */3');
          request.response.headers.set('etag', 'version-b');
        } else {
          request.response.contentLength = 3;
          request.response.headers.set('etag', 'version-b');
          request.response.add([7, 8, 9]);
        }
      });
      await fixture.seed([1, 2, 3, 4]);
      await fixture.run();
      expect(await fixture.output.readAsBytes(), [7, 8, 9]);
      expect(fixture.server.calls['/video.mp4'], 2);
    },
  );
  test('If-Range returning 200 replaces the old partial file', () async {
    final fixture = await _Fixture.create((request) {
      request.response.contentLength = 4;
      request.response.headers.set('etag', 'version-b');
      request.response.add([5, 6, 7, 8]);
    });
    await fixture.seed([1, 2]);
    await fixture.run();
    expect(await fixture.output.readAsBytes(), [5, 6, 7, 8]);
  });
}

final class _Fixture {
  _Fixture(this.directory, this.server);
  final Directory directory;
  final HttpTestServer server;
  final http = MediaHttpClient(allowPrivateNetworks: true);
  var validated = 0;
  List<int>? progress;
  File get output => File('${directory.path}/video.mp4');
  Uri get uri => server.baseUri.resolve('video.mp4');
  static Future<_Fixture> create(
    FutureOr<void> Function(HttpRequest) handler,
  ) async {
    final directory = await Directory.systemTemp.createTemp('mp4-resume');
    final fixture = _Fixture(directory, await HttpTestServer.start(handler));
    addTearDown(() async {
      fixture.http.close();
      await fixture.server.close();
      await directory.delete(recursive: true);
    });
    return fixture;
  }

  Future<void> seed(List<int> bytes) async {
    await File('${directory.path}/video.mp4.part').writeAsBytes(bytes);
    await File('${directory.path}/mp4-state.json').writeAsString(
      jsonEncode({'uri': uri.toString(), 'etag': 'version-a', 'total': 4}),
    );
  }

  Future<void> run() => downloadMp4(
    uri: uri,
    directory: directory,
    http: http,
    policy: HeaderPolicy({}),
    cancellation: CancellationToken(),
    maxBytes: 100,
    progress: (completed, total, bytes) async {
      progress = [completed, total, bytes];
    },
    validate: (file, token) async {
      validated++;
      expect(await file.length(), greaterThan(0));
    },
  );
}
