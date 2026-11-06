import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/catalog/data/provider_factory.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';
import '../../test_support/http_test_server.dart';

void main() {
  for (final metadata in [
    <String, Object?>{'provider_name': '资源方'},
    <String, Object?>{'provider_id': '', 'provider_name': '资源方'},
  ]) {
    test(
      'incomplete line metadata retains the default resolution route: $metadata',
      () async {
        final server = await HttpTestServer.start((request) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              request.uri.path == '/v1/catalog/movie'
                  ? {
                      'id': 'movie',
                      'title': '测试剧',
                      'episodes': [
                        {'title': '第1集', 'token': 'one'},
                      ],
                    }
                  : {
                      'line_options': [
                        {
                          ...metadata,
                          'resolved': true,
                          'resolve_required': false,
                          'minimum_user_level': 0,
                          'url': 'https://media.example/video.m3u8',
                        },
                      ],
                    },
            ),
          );
        });
        final http = MediaHttpClient(allowPrivateNetworks: true);
        addTearDown(() async {
          http.close();
          await server.close();
        });
        final provider = createVodProvider(
          VideoSource(
            id: 'kanju',
            name: '看剧AI',
            kind: 'kanju',
            endpoint: server.baseUri,
          ),
          DocumentClient(http),
        );
        final item = await provider.detail('movie');
        expect(item.lines, hasLength(1));
        final episode = item.lines.single.episodes.single;
        expect(episode.uri.queryParameters.containsKey('provider_id'), isFalse);
        expect((await provider.resolve(episode)).uri.host, 'media.example');
      },
    );
  }
}
