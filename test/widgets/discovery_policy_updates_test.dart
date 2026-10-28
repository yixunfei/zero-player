import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/discovery/presentation/discovery_page.dart';
import 'package:zero_player/features/settings/presentation/home_preferences.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';

late Directory root;
late AppServices services;
late String forest, shark, ordinary;

void main() {
  setUp(() async {
    root = await Directory.systemTemp.createTemp('discovery-policy-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.supervision.load();
    await services.settings.load();
    await services.settings.update({
      'filterAdult': false,
      'recommendation': 'off',
    });
    forest = await services.sources.saveManual(
      '森林',
      Uri.parse('https://slapibf.com/api'),
    );
    shark = await services.sources.saveManual(
      '鲨鱼',
      Uri.parse('https://shayuapi.com/api'),
    );
    ordinary = await services.sources.saveManual(
      '普通频道',
      Uri.parse('https://ordinary.test/api'),
    );
  });
  tearDown(() async {
    await services.close();
    await root.delete(recursive: true);
  });
  _menuCases();
  _taxonomyCase();
}

void _menuCases() {
  for (final home in [true, false]) {
    testWidgets(
      '${home ? 'homepage' : 'preferences'} removes adult sources from an open menu immediately',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: home
                  ? DiscoveryPage(services: services)
                  : HomePreferences(services: services),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
        List<String?> choices() => tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .items!
            .map((e) => e.value)
            .toList();
        expect(choices(), containsAll([forest, shark, ordinary]));
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final draft = await services.supervision.prepareCredentials(
            'fixture-password',
          );
          await services.supervision.saveCredentials(draft);
        });
        await tester.pumpAndSettle();
        expect(choices(), isNot(contains(forest)));
        expect(choices(), isNot(contains(shark)));
        expect(choices(), contains(ordinary));
        expect(find.text('森林'), findsNothing);
        expect(find.text('鲨鱼'), findsNothing);
        await tester.runAsync(
          () => services.supervision.execute(
            SensitiveOperation.channels,
            () => services.sources.setEnabled(shark, true),
            password: 'fixture-password',
          ),
        );
        await tester.pumpAndSettle();
        expect(choices(), isNot(contains(shark)));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

void _taxonomyCase() {
  testWidgets('homepage responds to adult taxonomy without a database event', (
    tester,
  ) async {
    await tester.runAsync(
      () => services.settings.update({'filterAdult': true}),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DiscoveryPage(services: services)),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    List<String?> choices() => tester
        .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .items!
        .map((e) => e.value)
        .toList();
    expect(choices(), contains(ordinary));
    services.contentPolicy.rememberCategories(ordinary, {
      '1': '国产色情',
      '2': '亚洲无码',
      '3': '强奸乱伦',
    });
    await tester.pump();
    expect(choices(), isNot(contains(ordinary)));
    await tester.pumpWidget(const SizedBox());
  });
}
