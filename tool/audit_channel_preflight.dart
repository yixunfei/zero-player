import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/header_policy.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/request_scheduler.dart';
import 'package:zero_player/features/live/data/live_playlist_parser.dart';
import 'package:zero_player/features/live/data/playlist_channels.dart';
import 'package:zero_player/features/live/domain/channel_probe_signature.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/radio/data/radio_snapshot.dart';
import 'package:zero_player/features/radio/domain/radio_subscription.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';
import 'package:zero_player/media/network/media_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'full local preflight of all bundled channels and every unique route',
    () async {
      final audit = ChannelAudit();
      try {
        await audit.load();
        await audit.check();
        await audit.publish();
      } finally {
        audit.http.close();
        audit.scheduler.close();
      }
    },
    timeout: const Timeout(Duration(hours: 2)),
  );
}

class ChannelAudit {
  ChannelAudit({
    this.allowLanOrigin,
    this.outputPrefix = 'channel-preflight',
    this.verifyOriginTransport = false,
  });
  final bool verifyOriginTransport;
  final bool Function(Uri)? allowLanOrigin;
  final String outputPrefix;
  final scheduler = RequestScheduler(globalLimit: 32, originLimit: 16);
  late final http = MediaHttpClient(
    scheduler: scheduler,
    allowLanOrigin: allowLanOrigin,
    maxConnectionsPerHost: 16,
  );
  final channels = <LiveChannel>[];
  final snapshots = <Map<String, Object?>>[];
  final sources = <Map<String, Object?>>[];
  final results = <Map<String, Object?>>[];
  final cache = <String, Future<Map<String, Object?>>>{};
  final _originChecks = <String, Future<bool>>{};
  final unreachableOrigins = <String>{};
  final _originCheckedAt = <String, int>{};
  int done = 0;
  Future<void> _checkpointWrites = Future<void>.value();

  Future<void> load() async {
    final lists =
        (jsonDecode(await File('assets/live_candidates.json').readAsString())
                as Map)['lists']
            as List;
    for (final entry in [
      ...lists,
      {'name': '内置广播', 'url': builtinRadioUrl, 'radio': true},
    ]) {
      final url = Uri.parse(entry['url'] as String);
      final headers = Map<String, String>.from(entry['headers'] as Map? ?? {});
      try {
        final doc = await DocumentClient(http).get(
          url,
          headers: headers,
          maxBytes: 8 * 1024 * 1024,
          networkTimeout: const Duration(seconds: 20),
        );
        final listId = stableId('$url');
        final parsed = entry['radio'] == true
            ? RadioSnapshot(
                text: doc.text,
                base: doc.uri,
                updatedAt: DateTime.now(),
              ).stations(
                RadioSubscription(name: entry['name'] as String, url: url),
              )
            : preparePlaylistChannels(
                parseLivePlaylist(doc.text, doc.uri, listId),
                const [],
                headers,
              );
        channels.addAll([
          for (final c in parsed)
            LiveChannel(
              id: c.id,
              listId: c.listId,
              name: c.name,
              urls: c.urls,
              headers: c.headers,
              headerOrigin: url,
              listName: entry['name'] as String,
            ),
        ]);
        snapshots.add({
          'url': '$url',
          'base': '${doc.uri}',
          'name': entry['name'],
          'text': doc.text,
          'radio': entry['radio'] == true,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
        sources.add({
          'url': '$url',
          'channels': parsed.length,
          'status': 'loaded',
        });
      } catch (error) {
        sources.add({
          'url': '$url',
          'status': 'unavailable',
          'error': error.runtimeType.toString(),
        });
      }
    }
    // ignore: avoid_print
    print(
      'Loaded ${channels.length} channels from ${sources.length} sources; testing all routes.',
    );
  }

  Future<Map<String, Object?>> route(LiveChannel channel, Uri uri) {
    final headers = channel.headersFor(uri);
    final key = jsonEncode([uri.toString(), headers]);
    return cache.putIfAbsent(key, () async {
      final origin = HeaderPolicy.origin(uri);
      if (verifyOriginTransport &&
          !await _originChecks.putIfAbsent(origin, () => _originReady(uri))) {
        return {
          'availability': 'inconclusive',
          'message': '源站 TCP/TLS 两次连接失败，无法发起媒体 HTTP 请求',
          'failureStage': 'transport',
          'checkedAt': _originCheckedAt[origin],
        };
      }
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final result = await probeMedia(
            http,
            uri,
            HeaderPolicy({uri: headers}),
            CancellationToken(),
            availabilityOnly: true,
            maxBytes: 128 * 1024,
            networkTimeout: const Duration(seconds: 8),
          );
          return {
            'availability': 'responding',
            'latencyMs': result.firstByte.inMilliseconds,
            'message': '本机实际媒体响应通过；未验证全程解码',
            'resolution': result.resolution,
            'languages': result.languages,
          };
        } on FormatException catch (error) {
          return {'availability': 'unavailable', 'message': error.message};
        } catch (_) {
          if (attempt == 1) {
            return {
              'availability': 'inconclusive',
              'message': '两次检测未确认媒体可用，等待复检',
            };
          }
        }
      }
      throw StateError('unreachable');
    });
  }

  Future<bool> _originReady(Uri uri) async {
    final origin = HeaderPolicy.origin(uri);
    for (var attempt = 0; attempt < 2; attempt++) {
      ConnectionTask<Socket>? task;
      try {
        http.targetPolicy.validateAccess(uri, originalOrigin: true);
        task = await http.targetPolicy.connect(uri, null, null);
        final socket = await task.socket.timeout(const Duration(seconds: 8));
        socket.destroy();
        return true;
      } on FormatException {
        // Let the media probe report the exact policy or URL rejection.
        return true;
      } catch (_) {
        // The same origin cannot serve any path without TCP/TLS connectivity.
      } finally {
        task?.cancel();
      }
    }
    unreachableOrigins.add(origin);
    _originCheckedAt[origin] = DateTime.now().millisecondsSinceEpoch;
    return false;
  }

  Future<void> check() async {
    var cursor = 0;
    final completed = {
      for (final row in results) '${row['id']}|${row['requestSignature']}',
    };
    done = results.length;
    Future<void> worker() async {
      while (cursor < channels.length) {
        final c = channels[cursor++];
        if (completed.contains('${c.id}|${channelProbeSignature(c)}')) continue;
        final routes = await Future.wait([
          for (final uri in c.urls)
            route(
              c,
              uri,
            ).then((result) => <String, Object?>{'url': '$uri', ...result}),
        ]);
        final passed = routes
            .where((r) => r['availability'] == 'responding')
            .toList();
        final status = passed.isNotEmpty
            ? 'responding'
            : routes.any((r) => r['availability'] == 'inconclusive')
            ? 'inconclusive'
            : 'unavailable';
        results.add({
          'id': c.id,
          'name': c.name,
          'listId': c.listId,
          'listName': c.listName,
          'signature': c.urls.join('|'),
          'requestSignature': channelProbeSignature(c),
          'checkedAt': routes.fold<int>(DateTime.now().millisecondsSinceEpoch, (
            time,
            route,
          ) {
            final checked = route['checkedAt'] as int? ?? time;
            return checked < time ? checked : time;
          }),
          'availability': status,
          'enabled': passed.isNotEmpty,
          'preferredUrl': passed.firstOrNull?['url'],
          'verifiedUrls': passed.map((r) => r['url']).toList(),
          'latencyMs': passed.firstOrNull?['latencyMs'],
          'message':
              passed.firstOrNull?['message'] ?? routes.firstOrNull?['message'],
          'resolution': passed.firstOrNull?['resolution'],
          'languages': passed.firstOrNull?['languages'] ?? [],
          'routes': routes,
        });
        done++;
        if (done % 25 == 0 || done == channels.length) {
          // ignore: avoid_print
          print(
            'Preflight $done/${channels.length}; passed ${results.where((r) => r['enabled'] == true).length}; unique routes ${cache.length}',
          );
          final checkpoint = jsonEncode({
            'completed': done,
            'total': channels.length,
            'results': results,
          });
          _checkpointWrites = _checkpointWrites.then((_) async {
            final file = File('build/$outputPrefix-progress.json.tmp');
            await file.writeAsString(checkpoint, flush: true);
            await file.rename('build/$outputPrefix-progress.json');
          });
          await _checkpointWrites;
        }
      }
    }

    await Future.wait(List.generate(32, (_) => worker()));
  }

  Future<void> publish() async {
    results.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final data = {
      'version': 2,
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'passedOnly': true,
      'sources': sources,
      'managedListIds': sources
          .map((c) => stableId(c['url'] as String))
          .toSet()
          .toList(),
      'scope':
          'All enumerated built-in live/radio channels; every unique URL and scoped headers; 128 KiB, 8 seconds, retry inconclusive once; media response, not full decode.',
      'results': results,
    };
    final text = const JsonEncoder.withIndent('  ').convert(data);
    await File('build/channel-preflight-full.json').writeAsString(text);
    await File('assets/catalogs/live/builtin.snapshots.json').writeAsString(
      jsonEncode({
        'lists': snapshots.where((s) => s['radio'] != true).toList(),
      }),
    );
    final radio = snapshots.where((s) => s['radio'] == true).single;
    await File(
      'assets/catalogs/radio/cn.snapshot.json',
    ).writeAsString(jsonEncode(radio));
    // ignore: avoid_print
    print(
      'Published ${results.length} channel results, ${cache.length} unique route checks; passed ${results.where((r) => r['enabled'] == true).length}.',
    );
  }
}
