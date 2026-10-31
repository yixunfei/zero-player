import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/application/live_probe.dart';
import 'package:zero_player/features/live/data/live_health_repository.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/data/m3u_parser.dart';
import 'package:zero_player/features/live/data/epg_parser.dart';
import 'package:zero_player/features/live/data/live_playlist_parser.dart';
import 'package:zero_player/features/live/domain/channel_identity.dart';
import 'package:zero_player/features/live/domain/channel_order.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/live/domain/live_health.dart';
import '../../test_support/http_test_server.dart';

void main() {
  _metadataTests();
  _probeTests();
  test('TXT URL headers remain attached to their own alternatives', () {
    final parsed = parseLivePlaylist(
      '电台,https://media.test/a|User-Agent=One#https://media.test/b|User-Agent=Two',
      Uri.parse('https://list.test/'),
      'list',
    );
    expect(parsed, hasLength(2));
    expect(parsed.first.headers['User-Agent'], 'One');
    expect(parsed.last.headers['User-Agent'], 'Two');
    expect(parsed.first.urls.single.path, '/a');
  });
}

void _metadataTests() {
  test(
    'quality prefixes merge while UHD, regions and sports-plus remain distinct',
    () {
      for (final name in [
        '(SD)CCTV1',
        '[HD]cctv-1',
        '（标清）CCTV-1 综合',
        'cctv1高清HD',
      ]) {
        expect(channelIdentity(name), 'CCTV1');
      }
      expect(channelIdentity('CCTV1 4K'), isNot('CCTV1'));
      expect(channelIdentity('CCTV5+'), isNot(channelIdentity('CCTV5')));
    },
  );

  test(
    'playlist HTTP options are parsed without invoking player properties',
    () {
      final channels = parseM3u(
        '''#EXTM3U
#EXTINF:-1,one
#EXTHTTP:{"User-Agent":"radio-test","Origin":"https://page.test","Host":"evil"}
#KODIPROP:inputstream.adaptive.stream_headers=Referer=https%3A%2F%2Fpage.test%2F
#KODIPROP:inputstream.adaptive.license_key=ignore
https://media.test/a|User-Agent=override
#EXTINF:-1,two
https://media.test/b
''',
        Uri.parse('https://list.test/list'),
        'test',
      );
      expect(channels.first.urls.single.toString(), 'https://media.test/a');
      expect(channels.first.headers, {
        'User-Agent': 'override',
        'Origin': 'https://page.test',
        'Referer': 'https://page.test/',
      });
      expect(channels.last.headers, isEmpty);
    },
  );

  test('measured healthy channels sort before the default CCTV-1', () {
    final channels = [
      const LiveChannel(id: 'a', listId: 'a', name: 'CCTV1', urls: []),
      LiveChannel(
        id: 'b',
        listId: 'b',
        name: '浙江卫视',
        urls: [Uri.parse('https://a.test/a')],
        health: const LiveHealth(availability: LiveAvailability.responding),
      ),
    ]..sort(compareChannels);
    expect(channels.first.id, 'b');
  });

  test(
    'EPG preserves display names for publishers using opaque identifiers',
    () async {
      final guide = await parseEpgGuideInBackground(
        '<tv><channel id="opaque"><display-name>CCTV-1 综合</display-name></channel></tv>',
        DateTime.now(),
      );
      expect(guide.names['opaque'], ['CCTV-1 综合']);
    },
  );
}

void _probeTests() {
  test('probe reaches fourth route and rejects a fake 200 response', () async {
    final requested = <String>[];
    final server = await HttpTestServer.start((request) {
      requested.add(request.uri.path);
      if (request.uri.path == '/ok') {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.add([0xff, 0xfb, ...List.filled(200, 0)]);
      } else if (request.uri.path == '/fake') {
        request.response.write('{"error":"denied"}');
      } else {
        request.response.statusCode = 404;
      }
    });
    final db = AppDatabase.memory();
    final http = MediaHttpClient(allowPrivateNetworks: true);
    final probe = LiveProbe(http, LiveHealthRepository(db));
    addTearDown(() async {
      await probe.close();
      http.close();
      await server.close();
      await db.close();
    });
    final channel = LiveChannel(
      id: 'a',
      listId: 'a',
      name: 'radio',
      urls: [
        for (final route in ['bad1', 'bad2', 'fake', 'ok'])
          server.baseUri.resolve(route),
      ],
    );
    final result = await probe.check(channel, CancellationToken());
    expect(result.availability, LiveAvailability.responding);
    expect(result.preferredUrl, '${server.baseUri}ok');
    expect(requested, ['/bad1', '/bad2', '/fake', '/ok']);
    final live = LiveRepository(db, DocumentClient(http));
    await live.setGuide('missing', Uri.parse('https://guide.test/epg.xml'));
    await expectLater(
      live.setGuide('missing', Uri.parse('file:///secret')),
      throwsFormatException,
    );
  });
}
