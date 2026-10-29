import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/playback/domain/feature_work_identity.dart';
import 'package:zero_player/features/settings/application/settings_controller.dart';
import 'package:zero_player/media/content_filter/filter_strategy.dart';
import 'package:zero_player/media/content_filter/fingerprints/audio_fingerprint.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_rule.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_repository.dart';
import 'package:zero_player/media/content_filter/fingerprints/feature_matcher.dart';
import 'package:zero_player/media/content_filter/fingerprints/sample_signature.dart';

void main() {
  _matchingTests();
  _scopeTests();
  _settingsTests();
}

void _matchingTests() {
  test('shifted content crosses probe boundary at an arbitrary timestamp', () {
    final rule = _rule();
    final pcm = Float64List(16000 * 9);
    pcm.setRange(3137 * 16, 5137 * 16, _wave(gain: .3));
    final matcher = FeatureMatcher([rule]);
    expect(matcher.add(_signature(pcm, 0, 4500), 0, 4500), isEmpty);
    final hits = matcher.add(_signature(pcm, 4000, 8500), 4000, 8500);
    expect(hits, hasLength(1));
    expect(hits.single.startMs, closeTo(3137, 75));
    expect(hits.single.range.end.inMilliseconds, closeTo(7137, 75));
    expect(rule.originStartMs, 10000);
  });

  test('silence, unrelated sound and reordered content are not matches', () {
    final rule = _rule();
    for (final frames in [
      audioFingerprint(Float64List(32000)),
      audioFingerprint(_wave(shift: 1900)),
      rule.audio.reversed.toList(),
    ]) {
      for (final strategy in FilterStrategy.values) {
        expect(
          FeatureMatcher([
            rule,
          ], strategy: strategy).add(SampleSignature([], frames, ''), 0, 2000),
          isEmpty,
        );
      }
    }
  });

  test(
    'aggressive tolerance differs from conservative without matching silence',
    () {
      final rule = _rule();
      final altered = rule.audio
          .map((f) => f.map((v) => v > 127 ? v - 22 : v + 22).toList())
          .toList();
      final signature = SampleSignature([], altered, '');
      expect(FeatureMatcher([rule]).add(signature, 20000, 22000), isEmpty);
      expect(
        FeatureMatcher([
          rule,
        ], strategy: FilterStrategy.aggressive).add(signature, 20000, 22000),
        hasLength(1),
      );
    },
  );

  test(
    'probe gaps never combine disjoint samples and reset clears suppression',
    () {
      final rule = _rule();
      final matcher = FeatureMatcher([rule]);
      matcher.add(
        SampleSignature([], rule.audio.take(4).toList(), ''),
        0,
        1000,
      );
      expect(
        matcher.add(
          SampleSignature([], rule.audio.skip(4).toList(), ''),
          2000,
          3000,
        ),
        isEmpty,
      );
      matcher.reset();
      final sample = SampleSignature([], rule.audio, '');
      expect(matcher.add(sample, 0, 2000), hasLength(1));
      matcher.reset();
      expect(matcher.add(sample, 0, 2000), hasLength(1));
    },
  );
}

void _scopeTests() {
  test(
    'channel and series rules persist and filter by work across episodes',
    () async {
      final db = AppDatabase.memory();
      final repository = FeatureRepository(db);
      try {
        await repository.save(_rule());
        await repository.save(
          _rule().copyWith(
            id: 'series-rule',
            scope: FeatureScope.series,
            seriesKey: 'same-work',
          ),
        );
        expect(
          await repository.applicable(
            sourceId: 'channel',
            seriesKey: 'same-work',
          ),
          hasLength(2),
        );
        expect(
          await repository.applicable(
            sourceId: 'channel',
            seriesKey: 'other-work',
          ),
          hasLength(1),
        );
        expect(
          (await repository.applicable(
            sourceId: 'other-channel',
            seriesKey: 'same-work',
          )).single.id,
          'series-rule',
        );
        expect(
          await repository.applicable(
            sourceId: 'other-channel',
            seriesKey: 'other-work',
          ),
          isEmpty,
        );
        final series = (await repository.list()).firstWhere(
          (r) => r.scope == FeatureScope.series,
        );
        await repository.setEnabled(series, false);
        expect(
          await repository.applicable(
            sourceId: 'other-channel',
            seriesKey: 'same-work',
            enabledOnly: true,
          ),
          isEmpty,
        );
        await repository.save(
          series.copyWith(label: 'new sample name', enabled: true),
        );
        expect((await repository.list()).length, 2);
        await repository.remove(series.id);
        expect(await repository.list(), hasLength(1));
      } finally {
        await db.close();
      }
    },
  );

  test('work identity requires metadata for cross-channel reuse', () {
    CatalogItem item(String source, {String year = ''}) => CatalogItem(
      sourceId: source,
      id: 'id',
      title: '同一部剧',
      year: year,
      category: '电视剧',
    );
    expect(
      featureWorkIdentity(item('a')),
      isNot(featureWorkIdentity(item('b'))),
    );
    expect(
      featureWorkIdentity(item('a', year: '2026')),
      featureWorkIdentity(item('b', year: '2026')),
    );
    expect(
      featureWorkIdentity(item('a', year: '2026')),
      isNot(featureWorkIdentity(item('b', year: '2025'))),
    );
    expect(
      () => _rule().copyWith(scope: FeatureScope.series),
      throwsFormatException,
    );
  });
}

void _settingsTests() {
  test(
    'defaults and all three strategies survive settings persistence',
    () async {
      final db = AppDatabase.memory();
      final settings = SettingsController(db);
      try {
        await settings.load();
        expect(settings.value.filterSkipSeconds, 20);
        expect(settings.value.filterStrategy, 'conservative');
        for (final strategy in FilterStrategy.values) {
          await settings.update({'filterStrategy': strategy.name});
          await settings.load();
          expect(settings.value.filterStrategy, strategy.name);
        }
        await expectLater(
          settings.update({'filterStrategy': 'unknown'}),
          throwsFormatException,
        );
      } finally {
        await settings.close();
        await db.close();
      }
    },
  );
}

SampleSignature _signature(Float64List pcm, int from, int to) =>
    SampleSignature(
      [],
      audioFingerprint(
        Float64List.sublistView(pcm, from * 16, to * 16),
        stepMs: 50,
      ),
      '',
      audioStepMs: 50,
    );

Float64List _wave({double gain = 1, double shift = 0}) => Float64List.fromList(
  List.generate(32000, (i) {
    final t = i / 16000;
    final frequency = 250 + (i ~/ 4000) * 180 + shift;
    return gain *
        (.3 * math.sin(2 * math.pi * frequency * t) +
            .15 * math.sin(2 * math.pi * frequency * 2.7 * t));
  }),
);

FeatureRule _rule() => FeatureRule(
  id: 'audio-rule',
  sourceId: 'channel',
  label: '口播',
  mode: FeatureMode.audio,
  sampleMs: 2000,
  beforeMs: 0,
  afterMs: 2000,
  visual: [],
  audio: audioFingerprint(_wave()),
  thumbnail: '',
  originKey: 'episode-one',
  originStartMs: 10000,
);
