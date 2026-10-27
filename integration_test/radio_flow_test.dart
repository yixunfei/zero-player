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
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/radio/data/radio_repository.dart';
import 'package:zero_player/features/radio/presentation/radio_player_controls.dart';
import '../test_support/http_test_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets('radio navigation, search, native playback and leave cleanup', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp(
      'zero-radio-integration-',
    );
    final services = AppServices.scoped(root, AppDatabase.memory());
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
    await services.db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
      'radio_snapshot:$builtinRadioUrl',
      jsonEncode({
        'text': '#EXTM3U\n#EXTINF:-1 group-title="测试",测试广播\nradio.wav\n',
        'base': fixture.baseUri.toString(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    ]);
    addTearDown(() async {
      await fixture.close();
      await services.close();
      await root.delete(recursive: true);
    });
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
    await tester.tap(find.byTooltip('暂停广播'));
    for (var i = 0; i < 20 && controller.playing; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.playing, isFalse);
    router.go('/');
    await tester.pumpAndSettle();
    expect(controller.active, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
