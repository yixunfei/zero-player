import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/media/content_filter/approved_media_server.dart';
import 'package:zero_player/media/content_filter/declared_ad_sampler.dart';
import 'package:zero_player/media/content_filter/filter_session.dart';
import 'package:zero_player/media/content_filter/filter_types.dart';
import 'package:zero_player/media/hls/timeline.dart';

void main() {
  _deferredTests();
  _gateTests();
  _lifecycleTests();
  _boundaryTests();
  _declaredSamplerTests();
}

void _deferredTests() {
  test(
    'a later match strips before-offset content before any publication',
    () async {
      final root = await Directory.systemTemp.createTemp('held_filter_');
      final sampler = _Sampler(const Duration(seconds: 32));
      final inspector = _DeferredInspector();
      final session = FilterSession(
        input: Uri.parse('http://127.0.0.1/input'),
        directory: root,
        sampler: sampler,
        inspector: inspector,
        startupBuffer: const Duration(seconds: 4),
      );
      inspector.session = session;
      try {
        await session.begin();
        session.observe(const Duration(seconds: 100));
        await _until(() => session.finished || session.failure != null);
        expect(session.failure, isNull);
        expect(
          session.timeline.slices.map(
            (s) => (s.originalStart.inMilliseconds, s.duration.inMilliseconds),
          ),
          [(0, 4000), (4000, 3000), (27000, 4000), (31000, 1000)],
        );
        expect(session.status.skipped.inSeconds, 20);
        expect(sampler.starts, [0, 4, 8, 27, 31]);
      } finally {
        await session.close();
      }
    },
  );
  test(
    'unfinished detection never flushes held content on cancellation',
    () async {
      final root = await Directory.systemTemp.createTemp('held_cancel_');
      final inspector = _DeferredInspector()..gate = Completer<void>();
      final session = FilterSession(
        input: Uri.parse('http://127.0.0.1/input'),
        directory: root,
        sampler: _Sampler(const Duration(seconds: 16)),
        inspector: inspector,
      );
      inspector.session = session;
      final ready = expectLater(session.begin(), throwsA(isA<FilterFailure>()));
      await _until(() => inspector.reachedMatch);
      final closing = session.close();
      inspector.gate!.complete();
      await closing;
      await ready;
      expect(session.timeline.slices, isEmpty);
    },
  );
}

final class _DeferredInspector implements DeferredSliceInspector {
  late FilterSession session;
  Completer<void>? gate;
  bool reachedMatch = false;
  @override
  Duration get retention => const Duration(seconds: 9);
  @override
  Future<void> prepare(CancellationToken token) async {}
  @override
  Future<void> close() async {}
  @override
  Future<FilterDecision> inspect(
    MediaSlice slice,
    CancellationToken token,
  ) async {
    if (slice.start.inSeconds != 8) {
      return const FilterDecision(FilterVerdict.allow);
    }
    expect(session.timeline.slices, isEmpty);
    reachedMatch = true;
    await gate?.future;
    return const FilterDecision(
      FilterVerdict.block,
      ranges: [RemovedInterval(Duration(seconds: 7), Duration(seconds: 27))],
    );
  }
}

void _declaredSamplerTests() {
  test(
    'removed manifest maps sample and duration to original coordinates',
    () async {
      final root = await Directory.systemTemp.createTemp('declared_sampler_');
      final delegate = _Sampler(const Duration(seconds: 8));
      final sampler = DeclaredAdSampler(
        delegate,
        () => const [
          RemovedInterval(Duration(seconds: 4), Duration(seconds: 12)),
        ],
      );
      final input = Uri.parse('http://127.0.0.1/input');
      final token = CancellationToken();
      try {
        expect(
          await sampler.duration(input, token),
          const Duration(seconds: 16),
        );
        final sample = await sampler.sample(
          input,
          const Duration(seconds: 12),
          const Duration(seconds: 4),
          root,
          token,
        );
        expect(delegate.starts, [4]);
        expect(sample.start, const Duration(seconds: 12));
        await expectLater(
          sampler.sample(
            input,
            const Duration(seconds: 2),
            const Duration(seconds: 4),
            root,
            token,
          ),
          throwsA(isA<FilterFailure>()),
        );
        expect(delegate.starts, [4]);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}

void _boundaryTests() {
  test('startup exceeding lookahead fails instead of deadlocking', () async {
    final fixture = await _Fixture.create([
      FilterVerdict.allow,
    ], startupBuffer: const Duration(seconds: 12));
    try {
      await expectLater(fixture.session.begin(), throwsA(isA<FilterFailure>()));
      expect(fixture.sampler.starts, isEmpty);
    } finally {
      await fixture.close();
    }
  });
  test(
    'declared range outside source duration blocks before sampling',
    () async {
      final fixture = await _Fixture.create(
        [FilterVerdict.allow],
        declaredAds: const [
          RemovedInterval(Duration(seconds: 1), Duration(seconds: 9)),
        ],
      );
      try {
        await expectLater(
          fixture.session.begin(),
          throwsA(isA<FilterFailure>()),
        );
        expect(fixture.sampler.starts, isEmpty);
      } finally {
        await fixture.close();
      }
    },
  );
  test('uncertainty after startup publishes no later media', () async {
    final fixture = await _Fixture.create([
      FilterVerdict.allow,
      FilterVerdict.uncertain,
      FilterVerdict.allow,
    ]);
    try {
      await fixture.session.begin();
      await _until(() => fixture.session.failure != null);
      expect(fixture.session.timeline.slices.length, 1);
      expect(fixture.sampler.starts, [0, 4]);
      final uri = fixture.server.register(fixture.session);
      expect((await fixture.get(uri.resolve('1.ts'))).$1, 404);
    } finally {
      await fixture.close();
    }
  });
}

void _gateTests() {
  test(
    'rejected bytes never become addressable and original positions survive',
    () async {
      final fixture = await _Fixture.create([
        FilterVerdict.allow,
        FilterVerdict.block,
        FilterVerdict.allow,
      ]);
      try {
        await fixture.session.begin();
        await _until(() => fixture.session.finished);
        final uri = fixture.server.register(fixture.session);
        final manifest = await fixture.get(uri);
        expect(manifest.$1, 200);
        expect(manifest.$2, contains('#EXT-X-ENDLIST'));
        expect(
          fixture.session.timeline.slices.map((s) => s.originalStart.inSeconds),
          [0, 8],
        );
        expect((await fixture.get(uri.resolve('1.ts'))).$2, 'approved:8');
        expect((await fixture.get(uri.resolve('2.ts'))).$1, 404);
        expect((await fixture.get(uri.resolve('sample.ts'))).$1, 404);
        expect((await fixture.get(uri, origin: 'https://example.org')).$1, 403);
      } finally {
        await fixture.close();
      }
    },
  );
  test('uncertain result blocks first playback and exposes no media', () async {
    final fixture = await _Fixture.create([FilterVerdict.uncertain]);
    try {
      await expectLater(fixture.session.begin(), throwsA(isA<FilterFailure>()));
      expect(fixture.session.timeline.slices, isEmpty);
      final uri = fixture.server.register(fixture.session);
      expect((await fixture.get(uri)).$1, 503);
      expect((await fixture.get(uri.resolve('0.ts'))).$1, 404);
      expect(fixture.session.failure, isNotNull);
    } finally {
      await fixture.close();
    }
  });
  test('detector error does not become allow', () async {
    final fixture = await _Fixture.create([FilterVerdict.allow]);
    fixture.inspector.failure = StateError('inference failed');
    try {
      await expectLater(fixture.session.begin(), throwsA(isA<FilterFailure>()));
      expect(fixture.session.timeline.slices, isEmpty);
    } finally {
      await fixture.close();
    }
  });
}

void _lifecycleTests() {
  test('paired declared advertisement skips sampler requests', () async {
    final fixture = await _Fixture.create(
      List.filled(4, FilterVerdict.allow),
      declaredAds: const [
        RemovedInterval(Duration(seconds: 4), Duration(seconds: 12)),
      ],
    );
    try {
      await fixture.session.begin();
      await _until(() => fixture.session.finished);
      expect(fixture.sampler.starts, [0, 12]);
      expect(fixture.inspector.calls, 2);
      expect(fixture.session.status.skipped, const Duration(seconds: 8));
    } finally {
      await fixture.close();
    }
  });
  test('lookahead is bounded until playback advances', () async {
    final fixture = await _Fixture.create(List.filled(12, FilterVerdict.allow));
    try {
      await fixture.session.begin();
      await _until(() => fixture.session.timeline.duration.inSeconds == 8);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fixture.sampler.starts, [0, 4]);
      fixture.session.observe(const Duration(seconds: 4));
      await _until(() => fixture.sampler.starts.length == 3);
      expect(fixture.sampler.starts, [0, 4, 8]);
    } finally {
      await fixture.close();
    }
  });
  test('cancellation suppresses late results and completes startup', () async {
    final fixture = await _Fixture.create([FilterVerdict.allow]);
    fixture.inspector.gate = Completer<void>();
    final ready = fixture.session.begin();
    final expected = expectLater(ready, throwsA(isA<FilterFailure>()));
    await _until(() => fixture.inspector.calls == 1);
    final closing = fixture.session.close();
    fixture.inspector.gate!.complete();
    await closing;
    await expected;
    expect(fixture.session.timeline.slices, isEmpty);
    await fixture.close();
  });
  test(
    'seek origin does not expose earlier frames in the output timeline',
    () async {
      final fixture = await _Fixture.create([FilterVerdict.allow], start: 8);
      try {
        await fixture.session.begin();
        expect(fixture.sampler.starts, [8]);
        expect(
          fixture.session.timeline.originalPosition(Duration.zero),
          const Duration(seconds: 8),
        );
      } finally {
        await fixture.close();
      }
    },
  );
}

Future<void> _until(bool Function() predicate) async {
  final watch = Stopwatch()..start();
  while (!predicate()) {
    if (watch.elapsed > const Duration(seconds: 3)) {
      fail('State did not converge');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

final class _Fixture {
  _Fixture(this.root, this.session, this.sampler, this.inspector);
  final Directory root;
  final FilterSession session;
  final _Sampler sampler;
  final _Inspector inspector;
  final server = ApprovedMediaServer();
  final client = HttpClient();
  static Future<_Fixture> create(
    List<FilterVerdict> decisions, {
    int start = 0,
    List<RemovedInterval> declaredAds = const [],
    Duration startupBuffer = const Duration(seconds: 4),
  }) async {
    final root = await Directory.systemTemp.createTemp('filter_test_');
    final sampler = _Sampler(Duration(seconds: start + decisions.length * 4));
    final inspector = _Inspector(decisions);
    final session = FilterSession(
      input: Uri.parse('http://127.0.0.1/input'),
      directory: Directory('${root.path}/work'),
      sampler: sampler,
      inspector: inspector,
      start: Duration(seconds: start),
      window: const Duration(seconds: 8),
      startupBuffer: startupBuffer,
      declaredAds: () => declaredAds,
    );
    final fixture = _Fixture(root, session, sampler, inspector);
    await fixture.server.start();
    return fixture;
  }

  Future<(int, String)> get(Uri uri, {String? origin}) async {
    final request = await client.getUrl(uri);
    if (origin != null) request.headers.set('Origin', origin);
    final response = await request.close();
    return (response.statusCode, await utf8.decodeStream(response));
  }

  Future<void> close() async {
    client.close(force: true);
    await server.close();
    await session.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

final class _Inspector implements SliceInspector {
  _Inspector(this.decisions);
  final List<FilterVerdict> decisions;
  Completer<void>? gate;
  Object? failure;
  int calls = 0;
  @override
  Future<void> prepare(CancellationToken cancellation) async {}
  @override
  Future<FilterDecision> inspect(
    MediaSlice slice,
    CancellationToken cancellation,
  ) async {
    final index = calls++;
    await gate?.future;
    if (failure != null) throw failure!;
    return FilterDecision(decisions[index], reason: 'test decision');
  }

  @override
  Future<void> close() async {}
}

final class _Sampler implements SliceSampler {
  _Sampler(this.total);
  final Duration total;
  final starts = <int>[];
  @override
  Future<Duration> duration(Uri input, CancellationToken cancellation) async =>
      total;
  @override
  Future<MediaSlice> sample(
    Uri input,
    Duration start,
    Duration duration,
    Directory directory,
    CancellationToken cancellation,
  ) async {
    starts.add(start.inSeconds);
    await directory.create(recursive: true);
    final file = await File('${directory.path}/sample.ts').writeAsString('raw');
    return MediaSlice(
      directory: directory,
      media: file,
      frames: [],
      audio: null,
      start: start,
      duration: duration,
    );
  }

  @override
  Future<MediaSlice> crop(
    MediaSlice slice,
    Duration start,
    Duration length,
    CancellationToken token,
  ) async {
    final directory = await slice.directory.parent.createTemp('crop_');
    return MediaSlice(
      directory: directory,
      media: slice.media,
      frames: [],
      audio: null,
      start: start,
      duration: length,
    );
  }

  @override
  Future<File> publish(
    MediaSlice slice,
    Duration outputStart,
    CancellationToken cancellation,
  ) => File(
    '${slice.directory.path}/approved.ts',
  ).writeAsString('approved:${slice.start.inSeconds}');
}
