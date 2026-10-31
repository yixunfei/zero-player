import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/settings/presentation/lan_access_dialog.dart';
import '../../test_support/mobile_app_fixture.dart';

void main() {
  testWidgets('LAN grants require explicit confirmation and can be revoked', (
    tester,
  ) async {
    final fixture = MobileAppFixture();
    await tester.runAsync(() async {
      await fixture.initialize();
      await fixture.services.lanAccess.load();
    });
    final services = fixture.services;
    addTearDown(() => fixture.finish(tester));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLanAccess(context, services),
              child: const Text('授权管理'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('授权管理'));
    await fixture.settle(tester);
    await tester.tap(find.text('添加授权'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'http://192.168.1.8:8080');
    await tester.tap(find.text('检查地址'));
    await tester.pumpAndSettle();
    expect(services.lanAccess.origins, isEmpty);
    expect(find.text('授权 http://192.168.1.8:8080'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(services.lanAccess.origins, isEmpty);
    await tester.tap(find.text('添加授权'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'http://192.168.1.8:8080');
    await tester.tap(find.text('检查地址'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await fixture.waitFor(tester, () => services.lanAccess.origins.isNotEmpty);
    await fixture.settle(tester);
    expect(services.lanAccess.origins, ['http://192.168.1.8:8080']);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('撤销'));
    await fixture.waitFor(tester, () => services.lanAccess.origins.isEmpty);
    await fixture.settle(tester);
    expect(services.lanAccess.origins, isEmpty);
  });
}
