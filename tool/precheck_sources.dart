import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/catalog/data/provider_factory.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';

/// Explicit developer-time check, never run during ordinary unit tests/startup.
void main() {
  test('record local builtin precheck', () async {
    final data =
        jsonDecode(await File('assets/source_candidates.json').readAsString())
            as Map;
    final inputs = [
      for (final url in (data['urls'] as List).cast<String>().toSet())
        (url, 'cms'),
      ('https://kanju3.com/', 'kanju'),
      ('https://wu5mv.com/', 'macCmsHtml'),
    ];
    final http = MediaHttpClient();
    final results = <Map<String, Object?>>[];
    var index = 0;
    Future<void> worker() async {
      while (index < inputs.length) {
        final (address, kind) = inputs[index++];
        final clock = Stopwatch()..start();
        final result = <String, Object?>{'url': address, 'kind': kind};
        try {
          final page = await createVodProvider(
            VideoSource(
              id: '',
              name: '',
              endpoint: Uri.parse(address),
              kind: kind,
            ),
            DocumentClient(http),
          ).browse();
          result.addAll({
            'status': 'available',
            'items': page.page.items.length,
            'defaultEnabled': true,
          });
        } catch (error) {
          final failure = error is RemoteFailure
              ? error
              : RemoteFailure(FailureKind.network, error.toString());
          // Transient connectivity, throttling and server failures are not
          // evidence that a channel should be disabled on every installation.
          final certain =
              failure.kind == FailureKind.invalid ||
              failure.kind == FailureKind.unsupported ||
              failure.kind == FailureKind.http &&
                  {400, 401, 403, 404, 405, 410, 451}.contains(failure.status);
          result.addAll({
            'status': certain ? 'unavailable' : 'inconclusive',
            'defaultEnabled': !certain,
            'failureKind': failure.kind.name,
            'httpStatus': failure.status,
            'reason': failure.message,
          });
        }
        result['elapsedMs'] = clock.elapsedMilliseconds;
        results.add(result);
      }
    }

    try {
      await Future.wait(List.generate(6, (_) => worker()));
    } finally {
      http.close();
    }
    results.sort((a, b) => (a['url'] as String).compareTo(b['url'] as String));
    final report = {
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'scope':
          'Local development machine; listing/API only, not media playback. Timeout, connectivity, rate-limit and 5xx are inconclusive.',
      'results': results,
    };
    final text = const JsonEncoder.withIndent('  ').convert(report);
    await File('assets/source_precheck.json').writeAsString(text);
    await File(
      'artifacts/interaction-source-precheck.json',
    ).writeAsString(text);
    // ignore: avoid_print
    print({
      for (final state in ['available', 'unavailable', 'inconclusive'])
        state: results.where((r) => r['status'] == state).length,
    });
  }, timeout: const Timeout(Duration(minutes: 15)));
}
