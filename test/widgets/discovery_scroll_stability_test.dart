import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/product_app.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/discovery/presentation/discovery_page.dart';
import 'package:zero_player/features/discovery/presentation/discovery_toolbar.dart';
import 'package:zero_player/features/sources/data/source_diagnostics_store.dart';
import 'package:zero_player/features/sources/domain/source_diagnostics.dart';
import '../../test_support/http_test_server.dart';
import '../../test_support/fake_player_engine.dart';

void main() {
  _backgroundPauseTest();
  _pausedSecurityTest();
  _pagingTests();
  _pageErrorTests();
  _phoneFlingTests();
}

void _backgroundPauseTest() {
  testWidgets(
    'a background probe pauses paging without replacing the active list',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await fixture.mount(tester);
        fixture
            .scroll(tester)
            .jumpTo(fixture.scroll(tester).position.maxScrollExtent - 100);
        await tester.pump();
        await fixture.settle(tester);
        final before = fixture.scroll(tester).offset;
        final requests = fixture.pages.length;
        final id = fixture.services.settings.value.homeChannel;
        await fixture.disable(tester);
        expect(fixture.scroll(tester).offset, closeTo(before, 1));
        expect(fixture.pages, hasLength(requests));
        expect(
          (await tester.runAsync(
            () => fixture.services.sources.find(id),
          ))!.enabled,
          isFalse,
        );
        expect(
          find.textContaining('自动加载已暂停', skipOffstage: false),
          findsOneWidget,
        );
        final menu = tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>, skipOffstage: false),
        );
        expect(menu.value, id);
        expect(
          menu.items!.singleWhere((entry) => entry.value == id).enabled,
          isFalse,
        );
        await tester.runAsync(
          () => fixture.services.sources.setEnabled(id, true),
        );
        await fixture.settle(tester);
        expect(fixture.scroll(tester).offset, closeTo(before, 1));
        fixture
            .scroll(tester)
            .jumpTo(fixture.scroll(tester).position.maxScrollExtent);
        await fixture.settle(tester);
        expect(
          fixture.pages,
          hasLength(requests),
          reason: 'Re-enabling must wait for an explicit refresh',
        );
        await tester.ensureVisible(find.text('刷新频道', skipOffstage: false));
        await tester.pumpAndSettle();
        await tester.tap(find.text('刷新频道'));
        await fixture.until(tester, () => fixture.pages.length > requests);
        expect(fixture.scroll(tester).offset, 0);
        expect(
          find.textContaining('频道状态已变化', skipOffstage: false),
          findsNothing,
        );
        expect(fixture.services.searchSourceId, id);
      } finally {
        await fixture.close(tester);
      }
    },
  );
}

void _pausedSecurityTest() {
  testWidgets(
    'a suspended feed still removes newly forbidden content immediately',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await fixture.mount(tester);
        fixture.scroll(tester).jumpTo(1500);
        await tester.pump();
        await fixture.disable(tester);
        final id = fixture.services.settings.value.homeChannel;
        expect(find.byType(SliverGrid, skipOffstage: false), findsOneWidget);
        fixture.services.contentPolicy.rememberCategories(id, {
          '1': '国产色情',
          '2': '亚洲无码',
          '3': '强奸乱伦',
        });
        await tester.pump();
        expect(find.byType(SliverGrid, skipOffstage: false), findsNothing);
        final menu = tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>, skipOffstage: false),
        );
        expect(menu.items!.map((entry) => entry.value), isNot(contains(id)));
        await fixture.settle(tester);
        expect(fixture.scroll(tester).offset, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );
}

void _pagingTests() {
  for (final aggregate in [false, true]) {
    testWidgets('downward paging preserves offset (aggregate: $aggregate)', (
      tester,
    ) async {
      final fixture = (await tester.runAsync(
        () => _Fixture.create(aggregate: aggregate),
      ))!;
      try {
        await fixture.mount(tester);
        for (var page = 2; page <= 4; page++) {
          fixture
              .scroll(tester)
              .jumpTo(fixture.scroll(tester).position.maxScrollExtent - 100);
          await tester.pump();
          final offset = fixture.scroll(tester).offset;
          await fixture.settle(tester);
          expect(fixture.pages, contains(page));
          expect(fixture.scroll(tester).offset, closeTo(offset, 1));
        }
        final offset = fixture.scroll(tester).offset;
        final requests = fixture.pages.length;
        final toolbar = tester.widget<DiscoveryToolbar>(
          find.byType(DiscoveryToolbar, skipOffstage: false),
        );
        toolbar.onChannel(toolbar.channel);
        toolbar.onLayout(toolbar.aggregate);
        if (!aggregate) {
          final chip = tester
              .widgetList<ChoiceChip>(
                find.byType(ChoiceChip, skipOffstage: false),
              )
              .singleWhere((chip) => chip.selected);
          chip.onSelected!(true);
        }
        await fixture.settle(tester);
        expect(fixture.scroll(tester).offset, closeTo(offset, 1));
        expect(
          fixture.pages,
          hasLength(requests),
          reason: 'Selecting the current filters must not reset the session',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    });
  }
}

void _pageErrorTests() {
  for (final aggregate in [false, true]) {
    testWidgets(
      'a late page error and retry preserve the list (aggregate: $aggregate)',
      (tester) async {
        final fixture = (await tester.runAsync(
          () => _Fixture.create(aggregate: aggregate),
        ))!;
        try {
          await fixture.mount(tester);
          for (var page = 2; page <= 3; page++) {
            fixture
                .scroll(tester)
                .jumpTo(fixture.scroll(tester).position.maxScrollExtent - 100);
            await tester.pump();
            await fixture.settle(tester);
          }
          fixture.failPage = 4;
          fixture
              .scroll(tester)
              .jumpTo(fixture.scroll(tester).position.maxScrollExtent - 100);
          await tester.pump();
          final before = fixture.scroll(tester).offset;
          await fixture.until(
            tester,
            () => find.text('重试加载', skipOffstage: false).evaluate().isNotEmpty,
          );
          expect(
            find.text('部分内容加载失败，已保留当前列表，可手动重试', skipOffstage: false),
            findsOneWidget,
          );
          expect(fixture.scroll(tester).offset, closeTo(before, 1));
          fixture.failPage = null;
          await tester.ensureVisible(find.text('重试加载', skipOffstage: false));
          await tester.pump();
          final retryOffset = fixture.scroll(tester).offset;
          await tester.tap(find.text('重试加载'));
          await fixture.settle(tester);
          expect(fixture.scroll(tester).offset, greaterThan(retryOffset - 150));
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.close(tester);
        }
      },
    );
  }
}

void _phoneFlingTests() {
  for (final aggregate in [false, true]) {
    testWidgets(
      'continuous phone flings through the real shell (aggregate: $aggregate)',
      (tester) async {
        final fixture = (await tester.runAsync(
          () => _Fixture.create(aggregate: aggregate),
        ))!;
        try {
          fixture.pageCount = 12;
          await fixture.mount(tester, fullApp: true);
          final controller = fixture.scroll(tester);
          for (var swipe = 0; swipe < 65; swipe++) {
            await tester.flingFrom(
              const Offset(145, 640),
              const Offset(0, -420),
              1400,
            );
            for (var frame = 0; frame < 15; frame++) {
              final before = controller.offset;
              await tester.pump(const Duration(milliseconds: 32));
              if (frame % 3 == 0) {
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 10)),
                );
              }
              expect(
                controller.offset,
                greaterThan(before - 500),
                reason: 'swipe=$swipe frame=$frame',
              );
            }
          }
          expect(fixture.pages.toSet().length, greaterThan(4));
          expect(controller.offset, greaterThan(5000));
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.close(tester);
        }
      },
    );
  }
}

final class _Fixture {
  _Fixture(this.root, this.services, this.server);
  final Directory root;
  final AppServices services;
  final HttpTestServer server;
  final pages = <int>[];
  int? failPage;
  int pageCount = 4;

  static Future<_Fixture> create({bool aggregate = false}) async {
    final root = await Directory.systemTemp.createTemp('discovery-scroll-');
    final services = AppServices.scoped(
      root,
      AppDatabase.memory(),
      allowPrivateNetworks: true,
      radioEngine: FakePlayerEngine.new,
      musicEngine: FakePlayerEngine.new,
    );
    HttpOverrides.runWithHttpOverrides(
      () => services.http,
      _RealHttpOverrides(),
    );
    await services.settings.load();
    await services.supervision.load();
    await services.gateway.start();
    late _Fixture fixture;
    final server = await HttpTestServer.start(
      (request) => fixture.serve(request),
    );
    fixture = _Fixture(root, services, server);
    final id = await services.sources.saveManual(
      '分页频道',
      server.baseUri.resolve('api'),
    );
    await services.settings.update({
      'homeChannel': id,
      'recommendation': 'off',
      'homeLayout': aggregate ? 'aggregate' : 'single',
      'navigationGuideSeen': true,
      'startFullscreen': false,
      'backgroundProbe': false,
    });
    return fixture;
  }

  void serve(HttpRequest request) {
    final page = int.parse(request.uri.queryParameters['pg'] ?? '1');
    final category = request.uri.queryParameters['t'] ?? '';
    pages.add(page);
    if (page == failPage) {
      request.response.statusCode = 400;
      return;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'page': page,
        'pagecount': pageCount,
        'class': [
          {'type_id': 1, 'type_name': '电影'},
          {'type_id': 2, 'type_name': '剧集'},
        ],
        'list': List.generate(
          24,
          (i) => {
            'vod_id': '$category-$page-$i',
            'vod_name': '作品 $category-$page-$i',
            'vod_pic': '',
            'vod_content': '固定简介',
            'type_name': '电影',
          },
        ),
      }),
    );
  }

  ScrollController scroll(WidgetTester tester) => tester
      .widget<CustomScrollView>(find.byKey(const ValueKey('discovery-scroll')))
      .controller!;

  Future<void> disable(WidgetTester tester) async {
    await tester.runAsync(
      () => SourceDiagnosticsStore(services.db).save(
        services.settings.value.homeChannel,
        SourceDiagnostics(state: 'inconclusive', checkedAt: DateTime.now()),
        applyPolicy: true,
      ),
    );
    await settle(tester);
  }

  Future<void> mount(WidgetTester tester, {bool fullApp = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: fullApp
            ? const ProductApp()
            : MaterialApp(
                home: Scaffold(body: DiscoveryPage(services: services)),
              ),
      ),
    );
    for (var i = 0; i < 80 && pages.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settle(tester);
    expect(
      pages,
      contains(1),
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    expect(scroll(tester).position.maxScrollExtent, greaterThan(2000));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 120 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      ready(),
      isTrue,
      reason:
          'pages=$pages offset=${scroll(tester).offset} texts=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(" | ")}',
    );
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    var closed = false;
    Object? error;
    final closing = services.close().then(
      (_) => closed = true,
      onError: (Object failure) {
        error = failure;
        closed = true;
        return true;
      },
    );
    for (var i = 0; i < 400 && !closed; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(closed, isTrue, reason: 'Application resources must close');
    await closing;
    if (error != null) throw error!;
    await tester.runAsync(() async {
      await server.close();
      await root.delete(recursive: true);
    });
  }
}

final class _RealHttpOverrides extends HttpOverrides {}
