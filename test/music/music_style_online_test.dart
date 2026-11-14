import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/music/data/music_catalog_api.dart';
import 'package:zero_player/features/music/data/music_chart_catalog.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/music_style_catalog.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import 'package:zero_player/features/music/domain/music_track.dart';

void main() {
  for (final provider in musicPlaylistProviders.keys) {
    test(
      'public categories, charts and distinct next pages: $provider',
      () async {
        final http = MediaHttpClient();
        addTearDown(http.close);
        final network = DocumentClient(http);
        final repository = MusicRepository(MyFreeMp3Client(network));
        final catalog = MusicStyleCatalog(repository);
        final charts = MusicChartCatalog(MusicCatalogApi(network));
        final token = CancellationToken();
        final results = await Future.wait([
          catalog.categories(provider, token),
          charts.charts(provider, token),
        ]);
        final (categories, ranks) = (results[0], results[1]);
        expect(categories.length, greaterThan(50));
        expect(ranks.length, greaterThan(20));
        final genre = categories.firstWhere((item) => item.name == '爵士');
        final first = await catalog.playlists(provider, genre, token);
        expect(first.next, isNotNull);
        final second = await catalog.playlists(
          provider,
          genre,
          token,
          cursor: first.next!,
        );
        expect(
          second.items
              .map((list) => list.id)
              .toSet()
              .difference(first.items.map((list) => list.id).toSet()),
          isNotEmpty,
        );
        final list = provider == 'qqPlaylist'
            ? (await catalog.playlists(
                provider,
                categories.firstWhere((item) => item.name == '官方歌单'),
                token,
              )).items.firstWhere((item) => (item.count ?? 0) > 50)
            : first.items.first;
        final readTracks = await catalog.open(list, token);
        final trackPage = await readTracks(0, token);
        expect(trackPage.items, isNotEmpty);
        expect(
          trackPage.items.every((t) => t.searchOnly && !t.canDownload),
          isTrue,
        );
        expect(trackPage.items.any((t) => t.artist.isNotEmpty), isTrue);
        expect(
          MusicTrack.fromJson(trackPage.items.first.toJson()).searchOnly,
          isTrue,
        );
        await expectLater(
          repository.resolve(trackPage.items.first, token),
          throwsFormatException,
        );
        if (trackPage.next case final next?) {
          final more = await readTracks(next, token);
          expect(
            more.items
                .map((track) => track.id)
                .toSet()
                .difference(trackPage.items.map((track) => track.id).toSet()),
            isNotEmpty,
          );
        }
        final rank = ranks.firstWhere((item) => item.name.contains('飙升'));
        final readRank = await charts.open(provider, rank.id, token);
        final rankFirst = await readRank(0, token);
        expect(rankFirst.next, isNotNull);
        final rankNext = await readRank(rankFirst.next!, token);
        expect(
          rankNext.items
              .map((item) => item.query)
              .toSet()
              .difference(rankFirst.items.map((item) => item.query).toSet()),
          isNotEmpty,
        );
        // ignore: avoid_print
        print(
          '$provider: ${categories.length} categories, ${ranks.length} ranks, '
          '${first.items.length}+${second.items.length} lists, '
          '${rankFirst.items.length}+${rankNext.items.length} chart songs',
        );
      },
      skip: !const bool.fromEnvironment('RUN_MUSIC_STYLE_ONLINE'),
    );
  }
}
