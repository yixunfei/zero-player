import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/media/content_filter/filter_types.dart';
import 'package:zero_player/media/content_filter/local_models.dart';
import 'package:zero_player/media/content_filter/local_runtime.dart';
import 'package:zero_player/media/content_filter/optional_resources.dart';
import 'package:zero_player/media/content_filter/resource_download.dart';
import 'package:zero_player/media/content_filter/runtime_catalog.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_inspector.dart';

void main() {
  _installationTests();
  _lifecycleTests();
}

void _installationTests() {
  test(
    'playback preparation never downloads missing enhancement assets',
    () async {
      final root = await Directory.systemTemp.createTemp('optional_missing_');
      final http = MediaHttpClient()
        ..close(); // Any attempt to download fails differently.
      try {
        final models = LocalModels(root, http);
        await expectLater(
          models.ensure(CancellationToken()),
          throwsA(
            isA<FilterFailure>().having(
              (e) => e.message,
              'message',
              contains('手动下载'),
            ),
          ),
        );
        expect(root.listSync(), isEmpty);
        final runtime = LocalRuntime(root, http);
        await expectLater(
          runtime.ensure(CancellationToken()),
          throwsA(isA<FilterFailure>()),
        );
        final inspector = FeatureInspector([]);
        await expectLater(
          inspector.prepare(CancellationToken()),
          throwsA(isA<FilterFailure>()),
        );
        await inspector.close();
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test('verified installer extracts only whitelisted binary paths', () async {
    final root = await Directory.systemTemp.createTemp('optional_archive_');
    final bytes = <int>[1, 2, 3, 4, 5];
    final archive = Archive()
      ..addFile(ArchiveFile('safe/runtime.dll', bytes.length, bytes))
      ..addFile(ArchiveFile('../escape.dll', bytes.length, bytes));
    final compressed = GZipEncoder().encode(TarEncoder().encode(archive));
    final package = RuntimePackage(
      ModelAsset(
        'runtime.tar.gz',
        '',
        compressed.length,
        sha256.convert(compressed).toString(),
      ),
      'safe/',
      [
        ModelAsset(
          'runtime.dll',
          '',
          bytes.length,
          sha256.convert(bytes).toString(),
        ),
      ],
    );
    final file = await File(
      '${root.path}/runtime.tar.gz',
    ).writeAsBytes(compressed);
    final output = await Directory('${root.path}/installed').create();
    try {
      await extractRuntime(file.path, output.path, package);
      expect(await File('${output.path}/runtime.dll').readAsBytes(), bytes);
      expect(await File('${root.path}/escape.dll').exists(), isFalse);
      await file.writeAsBytes([0]);
      await expectLater(
        extractRuntime(file.path, output.path, package),
        throwsA(isA<FilterFailure>()),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}

void _lifecycleTests() {
  test(
    'resource download rejects digest mismatch and deletes partial files',
    () async {
      final root = await Directory.systemTemp.createTemp('optional_download_');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) {
        r.response.add([1, 2, 3]);
        r.response.close();
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final file = File('${root.path}/asset');
      final asset = ModelAsset(
        'asset',
        'http://127.0.0.1:${server.port}/asset',
        3,
        'wrong',
      );
      try {
        await expectLater(
          downloadResource(http, file, asset, CancellationToken()),
          throwsA(isA<FilterFailure>()),
        );
        expect(root.listSync(), isEmpty);
        final token = CancellationToken()..cancel();
        await expectLater(
          downloadResource(http, file, asset, token),
          throwsA(isA<RequestCancelled>()),
        );
        expect(root.listSync(), isEmpty);
      } finally {
        http.close();
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'resource mutations are rejected while an enhanced session owns them',
    () async {
      final root = await Directory.systemTemp.createTemp('optional_busy_');
      final http = MediaHttpClient();
      final resources = OptionalResources(root, http)..users = 1;
      try {
        await expectLater(
          resources.download(Enhancement.ocr, CancellationToken()),
          throwsA(isA<FilterFailure>()),
        );
        await expectLater(
          resources.remove(Enhancement.asr),
          throwsA(isA<FilterFailure>()),
        );
        expect(root.listSync(), isEmpty);
      } finally {
        http.close();
        await root.delete(recursive: true);
      }
    },
  );
}
