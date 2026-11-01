import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/features/music/data/music_repository.dart';
import 'package:zero_player/features/music/data/myfreemp3_client.dart';

void main() {
  for (final provider in ['netease', 'audius', 'archive']) {
    test(
      'public source $provider searches and resolves metadata',
      () async {
        HttpOverrides.global = null;
        final http = MediaHttpClient();
        final repo = MusicRepository(MyFreeMp3Client(DocumentClient(http)));
        addTearDown(http.close);
        final result = await repo.search('piano', provider: provider);
        expect(result.tracks, isNotEmpty, reason: provider);
        expect(result.tracks.first.provider, provider);
        final track = await repo.resolve(
          result.tracks.first,
          CancellationToken(),
        );
        expect(track.url.scheme, 'https');
        expect(track.url.host, isNotEmpty);
        // ignore: avoid_print
        print(
          'MUSIC_SOURCE_OK $provider count=${result.tracks.length} mediaHost=${track.url.host}',
        );
      },
      skip: !const bool.fromEnvironment('RUN_MUSIC_ONLINE'),
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
