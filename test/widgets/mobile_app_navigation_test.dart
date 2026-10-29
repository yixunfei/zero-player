import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zero_player/app/shell.dart';
import '../../test_support/mobile_app_fixture.dart';

late MobileAppFixture fixture;
final platformCalls = <MethodCall>[];

void main() {
  setUp(() async {
    platformCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
    fixture = MobileAppFixture();
    await fixture.initialize();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  _basicNavigationTests();
  _stackTests();
  _viewportAndExitTests();
}

void _basicNavigationTests() {
  testWidgets('actual router root back confirms instead of exiting Android', (
    tester,
  ) async {
    await fixture.pump(tester);
    await tester.binding.handlePopRoute();
    await fixture.settle(tester);
    expect(find.text('退出 Zero Player？'), findsOneWidget);
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      isEmpty,
    );
    await tester.binding.handlePopRoute();
    await fixture.settle(tester);
    expect(find.text('退出 Zero Player？'), findsNothing);
    expect(
      platformCalls
          .where(
            (call) => call.method == 'SystemNavigator.setFrameworkHandlesBack',
          )
          .last
          .arguments,
      isTrue,
    );
    await fixture.finish(tester);
  });

  testWidgets('actual shell scroll hides navigation without an overlay menu', (
    tester,
  ) async {
    await fixture.pump(tester);
    final router = GoRouter.of(tester.element(find.byType(AppShell)));
    router.go('/settings');
    await fixture.settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar).hitTestable(), findsNothing);
    expect(find.byTooltip('展开导航').hitTestable(), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, 140));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
    await fixture.finish(tester);
  });

  testWidgets('phone startup never requests immersive app fullscreen', (
    tester,
  ) async {
    await fixture.pump(tester);
    expect(fixture.fullscreenCalls.where((call) => call.$1), isEmpty);
    expect(find.byType(NavigationBar), findsOneWidget);
    await fixture.finish(tester);
  });
}

void _stackTests() {
  testWidgets(
    'system back dismisses dialogs, drawer, pushed pages before root exit',
    (tester) async {
      await fixture.pump(tester);
      final context = tester.element(find.byType(AppShell));
      final router = GoRouter.of(context);
      router.push('/calendar');
      await fixture.settle(tester);
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('测试弹窗')),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await fixture.settle(tester);
      expect(find.text('测试弹窗'), findsNothing);
      expect(router.state.uri.path, '/calendar');
      await tester.binding.handlePopRoute();
      await fixture.settle(tester);
      expect(router.state.uri.path, '/');
      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer).hitTestable(), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Drawer).hitTestable(), findsNothing);
      expect(find.text('退出 Zero Player？'), findsNothing);
      router.go('/settings');
      await fixture.settle(tester);
      await tester.binding.handlePopRoute();
      await fixture.settle(tester);
      expect(router.state.uri.path, '/');
      expect(
        platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
        isEmpty,
      );
      await fixture.finish(tester);
    },
  );
}

void _viewportAndExitTests() {
  testWidgets('phone landscape and stored TV mode keep bottom navigation', (
    tester,
  ) async {
    await tester.runAsync(
      () => fixture.services.settings.update({'mode': 'television'}),
    );
    await fixture.pump(tester, size: const Size(844, 390));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(fixture.fullscreenCalls.where((call) => call.$1), isEmpty);
    await fixture.services.platform.fullscreen(true);
    expect(fixture.fullscreenCalls.last, (false, true));
    await fixture.services.platform.fullscreen(false);
    expect(fixture.fullscreenCalls.last, (false, false));
    expect(find.byType(NavigationBar), findsOneWidget);
    await fixture.finish(tester);
  });

  testWidgets('exit is dispatched only after explicit confirmation', (
    tester,
  ) async {
    await fixture.pump(tester);
    await tester.binding.handlePopRoute();
    await fixture.settle(tester);
    await tester.tap(find.text('继续使用'));
    await tester.pumpAndSettle();
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      isEmpty,
    );
    await tester.binding.handlePopRoute();
    await fixture.settle(tester);
    await tester.tap(find.text('退出'));
    await fixture.waitFor(
      tester,
      () => platformCalls.any((call) => call.method == 'SystemNavigator.pop'),
    );
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      hasLength(1),
    );
    await fixture.finish(tester);
  });
}
