import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';
import 'package:zero_player/features/sources/presentation/source_card.dart';
import 'package:zero_player/features/sources/presentation/source_details_dialog.dart';

late Directory root;
late AppServices services;
late VideoSource source;

void main() {
  setUp(() async {
    root = await Directory.systemTemp.createTemp('restricted-details-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.supervision.load();
    await services.settings.load();
    final id = await services.sources.saveManual(
      '受限测试来源',
      Uri.parse('https://restricted.test/api'),
      classification: 'adult',
    );
    source = (await services.sources.find(id))!;
    final draft = await services.supervision.prepareCredentials(
      'fixture-password',
    );
    await services.supervision.saveCredentials(draft);
  });
  tearDown(() async {
    await services.close();
    await root.delete(recursive: true);
  });
  testWidgets('restricted details show only the parental restriction notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSourceDetails(context, services, source),
              child: const Text('查看详情'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.text('禁止访问'), findsOneWidget);
    expect(find.textContaining('监管设置人已禁止访问'), findsOneWidget);
    _expectNoMetadata();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'an already open source dialog removes website data when policy changes',
    (tester) async {
      final ordinary = VideoSource(
        id: 'ordinary',
        name: '原普通源',
        endpoint: Uri.parse('https://restricted.test/api'),
      );
      services.contentPolicy.rememberSource(ordinary);
      await tester.pumpWidget(
        MaterialApp(
          home: SourceDetailsDialog(services: services, source: ordinary),
        ),
      );
      expect(find.text('https://restricted.test/api'), findsOneWidget);
      services.contentPolicy.rememberSource(
        VideoSource(
          id: ordinary.id,
          name: ordinary.name,
          endpoint: ordinary.endpoint,
          classification: 'adult',
        ),
      );
      await tester.pump();
      expect(find.text('禁止访问'), findsOneWidget);
      expect(find.text('原普通源'), findsNothing);
      _expectNoMetadata();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'management cards retain controls without exposing a restricted site',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SourceCard(
              source: source,
              repository: services.sources,
              selected: false,
              onSelected: (_) {},
              onDetails: () {},
              onAction: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('受限频道'), findsOneWidget);
      expect(find.text('受限测试来源'), findsNothing);
      expect(find.textContaining('restricted.test'), findsNothing);
      expect(find.byType(Switch), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

void _expectNoMetadata() {
  expect(find.textContaining('restricted.test'), findsNothing);
  expect(find.text('受限测试来源'), findsNothing);
  expect(find.text('接口网址'), findsNothing);
  expect(find.text('网站主页'), findsNothing);
  expect(find.text('IP 地址'), findsNothing);
  expect(find.text('刷新诊断'), findsNothing);
  expect(find.byType(SelectableText), findsNothing);
}
