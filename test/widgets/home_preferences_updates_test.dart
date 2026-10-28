import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/settings/presentation/home_preferences.dart';

void main() {
  late Directory directory;
  late AppServices services;
  late String id;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('home-preferences');
    services = AppServices.scoped(directory, AppDatabase.memory());
    await services.supervision.load();
    await services.settings.load();
    id = await services.sources.saveManual(
      'new-source',
      Uri.parse('https://source.test/api'),
    );
    await services.sources.setEnabled(id, false);
  });

  tearDown(() async {
    await services.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'home preferences reflect source enable changes while mounted',
    (tester) async {
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: HomePreferences(services: services)),
          ),
        );
        await tester.pumpAndSettle();
        List<String?> choices() => tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .items!
            .map((entry) => entry.value)
            .toList();
        expect(choices(), isNot(contains(id)));
        await tester.runAsync(() => services.sources.setEnabled(id, true));
        await tester.pumpAndSettle();
        expect(choices(), contains(id));
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        expect(find.text('new-source'), findsWidgets);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
