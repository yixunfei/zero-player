import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/music_style_catalog.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';
import 'package:zero_player/features/music/domain/music_track.dart';

void main() {
  for (final provider in musicPlaylistProviders.keys) {
    test(
      'public style playlists and metadata-only detail: $provider',
      () async {
        final http = MediaHttpClient();
        addTearDown(http.close);
        final repository = MusicRepository(
          MyFreeMp3Client(DocumentClient(http)),
        );
        final catalog = MusicStyleCatalog(repository);
        final token = CancellationToken();
        final lists = await catalog.search(provider, '爵士', token);
        expect(lists, isNotEmpty);
        final tracks = await catalog.tracks(lists.first, token);
        expect(tracks, isNotEmpty);
        expect(tracks.every((t) => t.searchOnly && !t.canDownload), isTrue);
        expect(tracks.any((t) => t.artist.isNotEmpty), isTrue);
        expect(MusicTrack.fromJson(tracks.first.toJson()).searchOnly, isTrue);
        await expectLater(
          repository.resolve(tracks.first, token),
          throwsFormatException,
        );
        // Distinguish metadata checks from native audio decoding.
        // ignore: avoid_print
        print('$provider: ${lists.length} playlists, ${tracks.length} tracks');
      },
      skip: !const bool.fromEnvironment('RUN_MUSIC_STYLE_ONLINE'),
    );
  }
}
