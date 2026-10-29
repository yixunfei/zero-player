import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/app/product_app.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/platform/platform_services.dart';
import 'fake_player_engine.dart';

final class MobileAppFixture {
  final fullscreenCalls = <(bool, bool)>[];
  late Directory directory;
  late AppServices services;
  bool _disposed = false;

  Future<void> initialize({String mode = 'auto'}) async {
    directory = await Directory.systemTemp.createTemp(
      'zero-mobile-regression-',
    );
    services = AppServices.scoped(
      directory,
      AppDatabase.memory(),
      radioEngine: FakePlayerEngine.new,
      platform: PlatformServices(
        applyFullscreen: (app, player) async {
          fullscreenCalls.add((app, player));
        },
      ),
    );
    await services.supervision.load();
    await services.settings.load();
    await services.settings.update({
      'navigationGuideSeen': true,
      'recommendation': 'off',
      'startFullscreen': true,
      'mode': mode,
      'backgroundProbe': false,
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    addTearDown(() async {
      await finish(tester);
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: const ProductApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await services.close();
    await directory.delete(recursive: true);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (_disposed) return;
    _disposed = true;
    var closed = false;
    Object? failure;
    final closing = services.close().then(
      (_) => closed = true,
      onError: (Object error) {
        failure = error;
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
    if (failure != null) throw failure!;
    await tester.runAsync(() => directory.delete(recursive: true));
  }

  Future<void> waitFor(WidgetTester tester, bool Function() complete) async {
    for (var i = 0; i < 400 && !complete(); i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(complete(), isTrue);
  }
}
