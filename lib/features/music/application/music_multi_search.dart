import 'dart:async';
import '../../../core/network/cancellation_token.dart';
import '../domain/music_track.dart';

typedef MusicSourceSearch =
    Future<MusicSearchResult> Function(
      String query, {
      int page,
      CancellationToken? cancellation,
      String provider,
    });

/// Each source owns its deadline; slow sources never hold back partial results.
final class MusicMultiSearch {
  MusicMultiSearch(this.search, {this.timeout = const Duration(seconds: 12)});
  final MusicSourceSearch search;
  final Duration timeout;
  static const providers = [
    'myfreemp3',
    'netease',
    'audius',
    'flacHi',
    'kugou',
  ];

  Future<void> run(
    String query, {
    required int page,
    required CancellationToken cancellation,
    required void Function(String, MusicSearchResult?, Object?) onResult,
    Set<String> favorites = const {},
  }) async {
    final ordered = [
      ...providers.where(favorites.contains),
      ...providers.where((id) => !favorites.contains(id)),
    ];
    var next = 0;
    Future<void> worker() async {
      while (!cancellation.isCancelled && next < ordered.length) {
        final provider = ordered[next++];
        final token = CancellationToken();
        final cancelled = Completer<MusicSearchResult>();
        final unlink = cancellation.listen(() {
          cancelled.completeError(const RequestCancelled());
          token.cancel();
        });
        try {
          final result =
              await Future.any<MusicSearchResult>([
                search(
                  query,
                  page: page,
                  provider: provider,
                  cancellation: token,
                ),
                cancelled.future,
              ]).timeout(
                timeout,
                onTimeout: () {
                  token.cancel();
                  throw TimeoutException('音乐渠道响应超时');
                },
              );
          if (!cancellation.isCancelled) onResult(provider, result, null);
        } catch (failure) {
          if (!cancellation.isCancelled) onResult(provider, null, failure);
        } finally {
          unlink();
        }
      }
    }

    await Future.wait(List.generate(3, (_) => worker()));
  }
}
