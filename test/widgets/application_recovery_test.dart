import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/application_fullscreen.dart';
import 'package:zero_player/app/navigation_guide.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/platform/platform_services.dart';
import 'package:zero_player/features/settings/application/settings_controller.dart';

void main() {
  testWidgets('Escape reaches ancestors when application fullscreen is off', (
    tester,
  ) async {
    final platform = PlatformServices(applyFullscreen: (_, _) async {});
    var escaped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () => escaped++,
          },
          child: ApplicationFullscreen(
            platform: platform,
            child: const Scaffold(body: Text('content')),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(escaped, 1);
    await platform.setAppFullscreen(true);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(platform.appFullscreen.value, isFalse);
    expect(escaped, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await platform.dispose();
  });

  testWidgets(
    'navigation guide can be dismissed after settings persistence fails',
    (tester) async {
      final db = AppDatabase.memory();
      final settings = SettingsController(db);
      final platform = PlatformServices(applyFullscreen: (_, _) async {});
      await db.close();
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showNavigationGuide(context, settings, platform: platform),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我知道了，开始使用'));
      await tester.pumpAndSettle();
      expect(find.text('引导状态保存失败，请重试。'), findsOneWidget);
      await tester.tap(find.text('稍后再说'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
