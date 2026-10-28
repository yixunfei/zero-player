import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/catalog/data/kanju_client.dart';
import 'package:zero_player/features/catalog/data/provider_factory.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';
import '../../test_support/http_test_server.dart';

void main() {
  test(
    'Kanju signs paginated requests and preserves chosen direct provider',
    () async {
      var signed = 0;
      final server = await HttpTestServer.start((request) {
        final timestamp = request.headers.value('x-ai-movie-timestamp')!;
        final nonce = request.headers.value('x-ai-movie-nonce')!;
        expect(
          request.headers.value('x-ai-movie-signature'),
          KanjuClient.signature(
            request.uri,
            timestamp,
            nonce,
          )['x-ai-movie-signature'],
        );
        signed++;
        final data = switch (request.uri.path) {
          '/v1/browse/catalog' => {
            'cards': [
              {'id': 'movie', 'title': '测试剧'},
            ],
            'pagination': {'has_more': true},
          },
          '/v1/catalog/movie' => {
            'id': 'movie',
            'title': '测试剧',
            'episodes': [
              {'title': '第1集', 'token': 'one'},
            ],
            'episode_pagination': {'has_more': true},
          },
          '/v1/catalog/movie/episodes' => {
            'episodes': [
              {'title': '第2集', 'token': 'two'},
            ],
            'episode_pagination': {'has_more': false},
          },
          _ => {
            'line_options': [
              {
                'provider_id': 'paid',
                'provider_name': '需登录',
                'resolved': false,
                'resolve_required': true,
                'url': 'resolve://ticket',
              },
              {
                'provider_id': 'direct',
                'provider_name': '直连',
                'resolved': true,
                'url': 'https://media.test/video.m3u8',
              },
            ],
          },
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(data));
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      try {
        final provider = createVodProvider(
          VideoSource(
            id: 'test',
            name: 'test',
            kind: 'kanju',
            endpoint: server.baseUri,
          ),
          DocumentClient(http),
        );
        expect((await provider.search('中文 空格')).pageCount, 2);
        final item = await provider.detail('movie');
        expect(item.lines.single.name, '直连');
        expect(item.lines.single.episodes.length, 2);
        expect(
          item.lines.single.episodes.last.uri.queryParameters['provider_id'],
          'direct',
        );
        expect(
          (await provider.resolve(item.lines.single.episodes.last)).uri.host,
          'media.test',
        );
        expect(signed, 5);
      } finally {
        http.close();
        await server.close();
      }
    },
  );
}
