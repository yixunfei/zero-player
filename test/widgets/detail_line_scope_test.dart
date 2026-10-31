import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/catalog/presentation/detail_page.dart';
import 'package:zero_player/features/catalog/presentation/source_choices.dart';
import 'package:zero_player/features/playback/presentation/line_selector.dart';
import '../../test_support/http_test_server.dart';

void main() {
  testWidgets(
    'detail reloads selected channel and movie without stale lines',
    _detailScope,
  );
  testWidgets(
    'reused selector cancels old movie probes and ignores their results',
    _selectorScope,
  );
  testWidgets(
    'line concurrency setting starts three independent origins together',
    _concurrency,
  );
  testWidgets(
    'live channel choices do not probe every channel as movie lines',
    _liveChoices,
  );
  testWidgets(
    'choosing a channel cancels queued API checks before dialog disposal',
    _channelChoice,
  );
}

Future<void> _channelChoice(WidgetTester tester) async {
  final fixture = (await tester.runAsync(_Fixture.start))!;
  addTearDown(() => tester.runAsync(fixture.close));
  fixture.holdApi = true;
  await tester.runAsync(
    () => fixture.services.settings.update({'probeConcurrency': 1}),
  );
  CatalogItem? selected;
  final first = CatalogItem(sourceId: fixture.a, id: '1', title: '渠道选择甲');
  final second = CatalogItem(sourceId: fixture.b, id: '1', title: '渠道选择乙');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SourceChoices(
          services: fixture.services,
          items: [first, second],
          onSelected: (item) => selected = item,
          onBlock: (_) async {},
        ),
      ),
    ),
  );
  int calls() =>
      (fixture.server.calls['/a'] ?? 0) + (fixture.server.calls['/b'] ?? 0);
  await _until(tester, () => calls() == 1);
  await tester.tap(find.text('渠道选择甲'));
  await tester.pump();
  expect(selected, same(first));
  fixture.detailsGate.complete();
  await _settleNetwork(tester);
  expect(
    calls(),
    1,
    reason: 'selector is still mounted during its route exit animation',
  );
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(fixture.close);
}

Future<void> _detailScope(WidgetTester tester) async {
  final fixture = (await tester.runAsync(_Fixture.start))!;
  addTearDown(() => tester.runAsync(fixture.close));
  Future<void> show(String source, String id) => tester.pumpWidget(
    ProviderScope(
      overrides: [servicesProvider.overrideWithValue(fixture.services)],
      child: MaterialApp(
        home: DetailPage(
          services: fixture.services,
          sourceId: source,
          remoteId: id,
        ),
      ),
    ),
  );
  await show(fixture.a, '1');
  await _until(
    tester,
    () => find.textContaining('当前渠道：甲渠道').evaluate().isNotEmpty,
  );
  expect(find.text('甲-1'), findsOneWidget);
  expect(fixture.server.calls['/b'], isNull);
  expect(find.byType(ChoiceChip), findsNWidgets(2));
  // A completed old FutureBuilder must disappear while the next detail loads.
  fixture.holdDetails = true;
  await show(fixture.b, '1');
  expect(find.text('甲-1'), findsNothing);
  await _until(tester, () => fixture.server.calls['/b'] == 1);
  await show(fixture.a, '2');
  await _until(tester, () => find.text('甲-2').evaluate().isNotEmpty);
  fixture.detailsGate.complete();
  await _settleNetwork(tester);
  expect(find.text('乙-1'), findsNothing);
  expect(find.textContaining('当前渠道：甲渠道'), findsOneWidget);
  expect(fixture.server.calls['/media/b/1'], isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(fixture.close);
}

Future<void> _selectorScope(WidgetTester tester) async {
  final fixture = (await tester.runAsync(_Fixture.start))!;
  addTearDown(() => tester.runAsync(fixture.close));
  fixture.holdMedia = true;
  final selected = <String>[];
  Future<void> show(CatalogItem item) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LineSelector(
          services: fixture.services,
          item: item,
          selected: -1,
          autoSelect: true,
          onSelected: (i) => selected.add('${item.id}:$i'),
        ),
      ),
    ),
  );
  await show(fixture.item('old', 'held.mp4'));
  await _until(tester, () => fixture.server.calls['/held.mp4'] == 1);
  await show(fixture.item('new', 'new.mp4'));
  await _until(tester, () => selected.isNotEmpty);
  fixture.mediaGate.complete();
  await _settleNetwork(tester);
  expect(selected, ['new:0']);
  expect(find.textContaining('old-line'), findsNothing);
  expect(find.textContaining('new-line'), findsOneWidget);
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(fixture.close);
}

Future<void> _concurrency(WidgetTester tester) async {
  final fixture = (await tester.runAsync(_Fixture.start))!;
  addTearDown(() => tester.runAsync(fixture.close));
  final gate = Completer<void>();
  final servers = <HttpTestServer>[];
  var started = 0;
  var selected = -1;
  await tester.runAsync(() async {
    await fixture.services.settings.update({'lineProbeConcurrency': 3});
    for (var i = 0; i < 4; i++) {
      servers.add(
        await HttpTestServer.start((r) async {
          started++;
          await gate.future;
          _media(r);
        }),
      );
    }
  });
  addTearDown(
    () => tester.runAsync(() async {
      if (!gate.isCompleted) gate.complete();
      for (final server in servers) {
        await server.close();
      }
    }),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LineSelector(
          services: fixture.services,
          item: CatalogItem(
            sourceId: fixture.a,
            id: 'parallel',
            title: 'parallel',
            lines: [
              for (var i = 0; i < servers.length; i++)
                PlayLine('line$i', [
                  Episode('1', servers[i].baseUri.resolve('movie.mp4')),
                ]),
            ],
          ),
          selected: -1,
          autoSelect: true,
          onSelected: (i) => selected = i,
        ),
      ),
    ),
  );
  await _until(tester, () => started == 3);
  await _settleNetwork(tester);
  expect(
    started,
    3,
    reason: 'must exceed the old fixed two and honor setting three',
  );
  gate.complete();
  await _until(tester, () => selected >= 0);
  expect(started, 4);
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(fixture.close);
}

Future<void> _liveChoices(WidgetTester tester) async {
  final fixture = (await tester.runAsync(_Fixture.start))!;
  addTearDown(() => tester.runAsync(fixture.close));
  var selected = -1;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LineSelector(
          services: fixture.services,
          item: CatalogItem(
            sourceId: 'live',
            id: 'live',
            title: 'live',
            lines: [
              PlayLine('央视一套', [
                Episode('线路1', fixture.server.baseUri.resolve('one.mp4')),
              ]),
              PlayLine('央视二套', [
                Episode('线路1', fixture.server.baseUri.resolve('two.mp4')),
              ]),
            ],
          ),
          selected: 0,
          onSelected: (i) => selected = i,
        ),
      ),
    ),
  );
  await _settleNetwork(tester);
  expect(fixture.server.calls, isEmpty);
  expect(find.text('直播频道'), findsOneWidget);
  await tester.tap(find.text('央视二套'));
  await tester.pump();
  expect(selected, 1);
  expect(find.text('线路尚未验证可用'), findsNothing);
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(fixture.close);
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
  expect(done(), isTrue);
}

Future<void> _settleNetwork(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void _media(HttpRequest request) {
  request.response.headers.contentType = ContentType('video', 'mp4');
  request.response.add([0, 0, 0, 24, 102, 116, 121, 112, 105, 115, 111, 109]);
}

class _RealHttpOverrides extends HttpOverrides {}

class _Fixture {
  bool closed = false;
  late Directory root;
  late AppServices services;
  late HttpTestServer server;
  late String a, b;
  bool holdDetails = false, holdMedia = false, holdApi = false;
  final detailsGate = Completer<void>(), mediaGate = Completer<void>();

  static Future<_Fixture> start() async {
    final f = _Fixture();
    f.root = await Directory.systemTemp.createTemp('zero-detail-scope-');
    f.server = await HttpTestServer.start(f.serve);
    f.services = AppServices.scoped(
      f.root,
      AppDatabase.memory(),
      allowPrivateNetworks: true,
    );
    HttpOverrides.runWithHttpOverrides(
      () => f.services.http,
      _RealHttpOverrides(),
    );
    await f.services.supervision.load();
    await f.services.settings.load();
    f.a = await f.services.sources.saveManual(
      '甲渠道',
      f.server.baseUri.resolve('a'),
    );
    f.b = await f.services.sources.saveManual(
      '乙渠道',
      f.server.baseUri.resolve('b'),
    );
    return f;
  }

  CatalogItem item(String id, String path) => CatalogItem(
    sourceId: a,
    id: id,
    title: id,
    lines: [
      PlayLine('$id-line', [Episode('1', server.baseUri.resolve(path))]),
    ],
  );

  Future<void> serve(HttpRequest r) async {
    final path = r.uri.path;
    if (path == '/a' || path == '/b') {
      if (holdApi && !r.uri.queryParameters.containsKey('ids')) {
        await detailsGate.future;
      }
      if (path == '/b' && holdDetails) await detailsGate.future;
      final id = r.uri.queryParameters['ids'] ?? '1';
      final name = path == '/a' ? '甲' : '乙';
      final url = server.baseUri.resolve('media$path/$id');
      r.response.write(
        jsonEncode({
          'list': [
            {
              'vod_id': id, 'vod_name': '$name-$id',
              // Upstream line labels may resemble other channel names.
              'vod_play_from': r'乙渠道同名线路$$$内部备用',
              'vod_play_url': [
                r'正片$'
                    '$url',
                r'正片$'
                    '$url',
              ].join(r'$$$'),
            },
          ],
        }),
      );
    } else {
      if (path == '/held.mp4' && holdMedia) await mediaGate.future;
      _media(r);
    }
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (!detailsGate.isCompleted) detailsGate.complete();
    if (!mediaGate.isCompleted) mediaGate.complete();
    await services.close();
    await server.close();
    await root.delete(recursive: true);
  }
}
