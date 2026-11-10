import 'dart:async';

import '../../../core/network/cancellation_token.dart';
import '../data/music_audio_probe.dart';
import '../data/music_repository.dart';
import '../domain/music_match.dart';
import '../domain/music_track.dart';
import 'music_multi_search.dart';

typedef MusicProbe =
    Future<MusicAudioSample> Function(MusicTrack, CancellationToken);

/// Samples are short-lived because sources can issue expiring media URLs.
final class MusicPreflight {
  MusicPreflight(this.repository, {MusicProbe? probe})
    : _probe =
          probe ??
          ((track, token) => probeMusicAudio(repository, track, token));

  final MusicRepository repository;
  final MusicProbe _probe;
  final _candidates = <Object, Map<String, MusicTrack>>{};
  final _matches = <Object, Future<void>>{};
  final _searchedAt = <Object, DateTime>{};
  final _samples = <String, ({DateTime expires, MusicAudioSample? sample})>{};
  final _pending = <String, Future<void>>{};
  final _updates = StreamController<void>.broadcast();
  Stream<void> get updates => _updates.stream;
  CancellationToken _session = CancellationToken();

  Object _identity(MusicTrack track) => musicIdentity(track) ?? track.key;

  Iterable<MusicTrack> _known(MusicTrack track) =>
      _candidates[_identity(track)]?.values ?? const [];

  Future<void> prepare(
    MusicTrack track, {
    Iterable<MusicTrack> alternatives = const [],
    bool findMatches = false,
    bool urgent = false,
  }) async {
    if (!repository.allowed(track)) return;
    final key = _identity(track);
    final known = _candidates.remove(key) ?? <String, MusicTrack>{};
    _candidates[key] = known;
    for (final item in [track, ...alternatives]) {
      if (known.length >= 12) break;
      if (!item.searchOnly &&
          repository.allowed(item) &&
          (item.key == track.key ||
              (key is (String, String) && musicIdentity(item) == key))) {
        known[item.key] = item;
      }
    }
    while (_candidates.length > 96) {
      final oldest = _candidates.keys.first;
      _candidates.remove(oldest);
      _searchedAt.remove(oldest);
    }
    await Future.wait([
      for (final item in known.values.toList()) _measure(item),
      if (findMatches && track.artist.trim().isNotEmpty)
        _discover(track, known, urgent: urgent),
    ]);
  }

  Future<void> _discover(
    MusicTrack track,
    Map<String, MusicTrack> known, {
    required bool urgent,
  }) async {
    final key = _identity(track);
    if (_matches[key] case final pending?) return pending;
    if (_matches.length >= (urgent ? 5 : 4)) return;
    final last = _searchedAt[key];
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 2)) {
      return;
    }
    final session = _session;
    final probing = <Future<void>>[];
    final query = '${track.title} ${track.artist}';
    final pending = MusicMultiSearch(repository.search)
        .run(
          query,
          page: 1,
          cancellation: session,
          onResult: (_, result, _) {
            if (session.isCancelled || !repository.allowed(track)) return;
            final match = result?.tracks
                .where(
                  (candidate) =>
                      matchesMusic(track, candidate) &&
                      repository.allowed(candidate),
                )
                .firstOrNull;
            if (match == null) return;
            known[match.key] = match;
            probing.add(_measure(match));
          },
        )
        .then((_) => Future.wait(probing))
        .then<void>((_) {});
    _matches[key] = pending;
    try {
      await pending;
      if (!session.isCancelled) _searchedAt[key] = DateTime.now();
    } finally {
      if (_matches[key] == pending) _matches.remove(key);
    }
  }

  Future<void> _measure(MusicTrack track) async {
    if (_pending[track.key] case final pending?) return pending;
    final cached = _samples[track.key];
    final minValidity = Duration(seconds: cached?.sample == null ? 0 : 25);
    if ((cached?.expires.isAfter(DateTime.now().add(minValidity)) ?? false) ||
        _pending.length >= 32) {
      return;
    }
    final session = _session;
    final token = CancellationToken();
    final unlink = session.listen(token.cancel);
    final deadline = Timer(const Duration(seconds: 7), token.cancel);
    final pending = _sample(track, token, session);
    _pending[track.key] = pending;
    try {
      await pending;
    } finally {
      deadline.cancel();
      unlink();
      if (_pending[track.key] == pending) _pending.remove(track.key);
    }
  }

  Future<void> _sample(
    MusicTrack track,
    CancellationToken token,
    CancellationToken session,
  ) async {
    MusicAudioSample? sample;
    try {
      sample = await _probe(track, token).timeout(const Duration(seconds: 7));
      token.check();
    } catch (_) {
      sample = null;
    }
    if (session.isCancelled || (sample == null && prepared(track) != null)) {
      return;
    }
    _cache(track, sample);
    if (sample != null) _updates.add(null);
  }

  void markFailed(MusicTrack track) => _cache(track, null);

  void _cache(MusicTrack track, MusicAudioSample? sample) {
    _samples.remove(track.key);
    _samples[track.key] = (
      expires: DateTime.now().add(Duration(seconds: sample == null ? 25 : 75)),
      sample: sample,
    );
    if (_samples.length > 128) _samples.remove(_samples.keys.first);
  }

  bool _fresh(String key) =>
      _samples[key]?.expires.isAfter(DateTime.now()) ?? false;

  MusicAudioSample? prepared(MusicTrack track) {
    final sample = _samples[track.key]?.sample;
    return sample != null &&
            _fresh(track.key) &&
            repository.allowed(sample.track)
        ? sample
        : null;
  }

  MusicAudioSample? best(
    MusicTrack track,
    String strategy, {
    Set<String> excludedProviders = const {},
    String? provider,
  }) {
    final samples = [
      for (final item in _known(track))
        if (_fresh(item.key) &&
            !excludedProviders.contains(item.provider) &&
            (provider == null || provider == item.provider))
          if (prepared(item) case final sample?)
            if (item.key == track.key || matchesMusic(track, sample.track))
              sample,
    ];
    samples.sort((a, b) {
      int quality(MusicAudioSample sample) =>
          sample.lossless ? 1000 : sample.mp3Kbps;
      final qualityOrder = quality(b).compareTo(quality(a));
      if (strategy == 'quality' && qualityOrder != 0) return qualityOrder;
      int score(MusicAudioSample value) =>
          value.latency.inMilliseconds -
          (strategy == 'balanced' ? quality(value) ~/ 2 : 0);
      final latency = score(a).compareTo(score(b));
      return latency != 0 ? latency : qualityOrder;
    });
    return samples.firstOrNull;
  }

  bool unavailable(MusicTrack track) =>
      _fresh(track.key) && _samples[track.key]?.sample == null;

  void reset() {
    _session.cancel();
    _session = CancellationToken();
    _candidates.clear();
    _matches.clear();
    _searchedAt.clear();
    _samples.clear();
    _pending.clear();
  }

  Future<void> close() {
    reset();
    return _updates.close();
  }
}
