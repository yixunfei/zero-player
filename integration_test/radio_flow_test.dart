import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/product_app.dart';
import 'package:zero_player/app/shell.dart';
import 'package:zero_player/core/network/file_response.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/radio/data/radio_repository.dart';
import 'package:zero_player/features/radio/presentation/radio_player_controls.dart';
import '../test_support/http_test_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets(
    'radio navigation, search, native playback and background controls',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'zero-radio-integration-',
      );
      final services = AppServices.scoped(
        root,
        AppDatabase.memory(),
        allowPrivateNetworks: true,
      );
      final fixture = await HttpTestServer.start((request) async {
        const configuredProject = String.fromEnvironment('PROJECT_ROOT');
        final project = configuredProject.isEmpty
            ? Directory.current.path
            : configuredProject;
        await serveLocalFile(
          request,
          File('$project/test_support/generated/radio.wav'),
          contentType: 'audio/wav',
        );
      });
      await _prepareServices(services);
      await services.db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
        'radio_snapshot:$builtinRadioUrl',
        jsonEncode({
          'text':
              '#EXTM3U\n#EXTINF:-1 group-title="测试",CCTV-13新闻伴音\nradio.wav\n'
              '#EXTINF:-1 group-title="测试",测试广播\nradio.wav\n',
          'base': fixture.baseUri.toString(),
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      ]);
      addTearDown(() async {
        await fixture.close();
        await services.close();
        await root.delete(recursive: true);
      });
      final initial = await services.radio.load();
      await services.channelPreflight.refresh(
        initial.stations.expand((c) => c.entries).toList(),
        CancellationToken(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [servicesProvider.overrideWithValue(services)],
          child: const ProductApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(AppShell)));
      router.go('/radio');
      await tester.pumpAndSettle();
      expect(find.text('在线广播 · 实验阶段'), findsOneWidget);
      await _categoryFilters(tester);
      await tester.enterText(find.byType(TextField), '不存在');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的电台'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '测试');
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试广播'));
      final controller = tester
          .widget<RadioPlayerControls>(find.byType(RadioPlayerControls))
          .controller;
      for (var i = 0; i < 60 && !controller.playing; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(controller.playing, isTrue);
      expect(controller.error, isNull);
      await tester.tap(find.byTooltip('收起广播播放器'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
      expect(controller.playing, isTrue);
      await tester.tap(find.byTooltip('展开广播播放器'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
      await tester.tap(find.byTooltip('暂停广播'));
      for (var i = 0; i < 20 && controller.playing; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.playing, isFalse);
      await controller.toggle();
      router.go('/');
      await tester.pumpAndSettle();
      expect(controller.active, isTrue);
      expect(controller.playing, isTrue);
      await _expandAndReturn(tester);
      expect(controller.playing, isTrue);
      await tester.tap(find.byTooltip('停止广播'));
      await tester.pumpAndSettle();
      expect(controller.active, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _categoryFilters(WidgetTester tester) async {
  final first = tester.widgetList<ListTile>(find.byType(ListTile)).first;
  expect((first.title as Text).data, '测试广播');
  await tester.tap(find.widgetWithText(ChoiceChip, '电视伴听'));
  await tester.pumpAndSettle();
  expect(find.text('测试广播'), findsNothing);
  expect(find.text('CCTV-13新闻伴音'), findsOneWidget);
  await tester.tap(find.widgetWithText(ChoiceChip, '广播电台'));
  await tester.pumpAndSettle();
  expect(find.text('CCTV-13新闻伴音'), findsNothing);
}

Future<void> _prepareServices(AppServices services) async {
  await services.supervision.load();
  await services.settings.load();
  await services.settings.update({
    'navigationGuideSeen': true,
    'startFullscreen': false,
    'recommendation': 'off',
    'backgroundProbe': false,
  });
  await services.platform.initialize();
  await services.store.initialize();
  await services.gateway.start();
}

Future<void> _expandAndReturn(WidgetTester tester) async {
  await tester.tap(find.byTooltip('展开广播页面'));
  await tester.pumpAndSettle();
  expect(find.text('在线广播 · 实验阶段'), findsOneWidget);
  await tester.tap(find.byTooltip('收起广播页面'));
  await tester.pumpAndSettle();
  expect(find.text('在线广播 · 实验阶段'), findsNothing);
  expect(find.byTooltip('展开广播页面'), findsOneWidget);
}
