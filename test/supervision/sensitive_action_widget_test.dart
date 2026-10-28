import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/widgets.dart';
import 'package:zero_player/features/supervision/presentation/sensitive_action.dart';
import 'package:zero_player/features/supervision/presentation/credential_dialogs.dart';
import '../../test_support/supervision_fixture.dart';

void main() {
  _registerCase0();
  _registerCase1();
}

void _registerCase0() {
  testWidgets(
    'cancel and wrong password do nothing; each successful action re-prompts',
    (tester) async {
      final f = SupervisionFixture();
      await tester.runAsync(f.configure);
      expect(f.guard.configured, isTrue);
      addTearDown(f.close);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => perform(
                  context,
                  () => runSensitive(
                    context,
                    f.guard,
                    SensitiveOperation.channels,
                    () async {
                      f.guard.require(SensitiveOperation.channels);
                      calls++;
                    },
                  ),
                ),
                child: const Text('启用频道'),
              ),
            ),
          ),
        ),
      );
      await _openPrompt(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await _openPrompt(tester);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.runAsync(() async {
        await tester.tap(find.text('验证并继续'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.textContaining('不正确'), findsOneWidget);
      await _openPrompt(tester);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'safe-test-password');
      await tester.runAsync(() async {
        await tester.tap(find.text('验证并继续'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(calls, 1);
      await _openPrompt(tester);
      await tester.pumpAndSettle();
      expect(find.text('验证监管密码'), findsOneWidget);
      expect(calls, 1);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    },
  );
}

void _registerCase1() {
  testWidgets('recovery setup requires explicit saved-code acknowledgement', (
    tester,
  ) async {
    bool? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                saved = await confirmRecoveryCode(
                  context,
                  'test-recovery-code',
                );
              },
              child: const Text('设置'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '完成设置'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成设置'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
  });
}

Future<void> _openPrompt(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.text('启用频道'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
}
