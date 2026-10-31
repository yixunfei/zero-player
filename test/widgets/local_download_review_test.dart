import 'dart:io';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/downloads/presentation/download_selection.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/domain/player_engine.dart';
import 'package:zero_player/features/playback/presentation/local_video_page.dart';
import 'package:zero_player/features/playback/presentation/player_transport.dart';
import 'package:zero_player/media/gateway/offline_server.dart';
import '../../test_support/fake_player_engine.dart';

late Directory root;
late AppServices services;
late PlaybackController controller;

void main() {
  setUp(() async {
    root = await Directory.systemTemp.createTemp('review-ui-');
    services = AppServices.scoped(root, AppDatabase.memory());
    await services.settings.load();
    await services.supervision.load();
    await services.store.initialize();
    controller = PlaybackController(services, FakePlayerEngine());
  });
  tearDown(() async {
    await controller.close();
    await services.close();
    await root.delete(recursive: true);
  });

  _missingRecordTest();
  _landscapeSelectionTest();
  _offlineMarkTest();
}

void _missingRecordTest() {
  testWidgets('retry after a missing local record opens the file picker', (
    tester,
  ) async {
    final previous = FileSelectorPlatform.instance;
    final picker = _Picker();
    FileSelectorPlatform.instance = picker;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    await services.db.write('INSERT INTO app_meta(key,value) VALUES(?,?)', [
      'local_video:gone',
      '${root.path}/missing.mp4',
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalVideoPage(services: services, id: 'gone'),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择视频文件'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _landscapeSelectionTest() {
  testWidgets(
    'landscape selection scrolls with long titles and enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(568, 320);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final previous = FileSelectorPlatform.instance;
      final longPath = 'K:\\${'很长的文件夹名称\\' * 40}';
      FileSelectorPlatform.instance = _Picker(directory: longPath);
      addTearDown(() => FileSelectorPlatform.instance = previous);
      final episode = Episode(
        '非常长的集数标题' * 8,
        Uri.parse('https://example.invalid/a.mp4'),
      );
      final item = CatalogItem(
        sourceId: 'test',
        id: 'long',
        title: '超长影片名称' * 12,
        lines: [
          PlayLine('main', [episode]),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => selectDownloads(context, services, item, 0),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存位置'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('保存位置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存位置'));
      await tester.pumpAndSettle();
      expect(find.text(longPath), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('全选'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('全选'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('下载 1 集'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('下载 1 集'));
      await tester.pumpAndSettle();
      expect(find.text('下载 1 集').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

void _offlineMarkTest() {
  testWidgets('offline marking is disabled in controller and transport', (
    tester,
  ) async {
    final item = CatalogItem(sourceId: 'local', id: 'one', title: 'Video');
    controller.request = PlaybackRequest(
      item,
      offline: OfflineSession(Uri.parse('http://127.0.0.1:1/local.mp4'), () {}),
      mediaKind: PlaybackMediaKind.local,
    );
    controller.state = const PlaybackSnapshot(
      duration: Duration(seconds: 30),
      position: Duration(seconds: 8),
      playing: true,
    );
    expect(controller.request!.supportsMarks, isFalse);
    expect(
      PlaybackRequest(
        item,
        offline: controller.request!.offline,
        mediaKind: PlaybackMediaKind.online,
      ).supportsMarks,
      isFalse,
    );
    expect(controller.markFeatureStart, throwsFormatException);
    await expectLater(controller.mark(), throwsFormatException);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerTransport(
            controller: controller,
            fullscreen: false,
            onFullscreen: () {},
            onOptions: () {},
            onMark: () {},
            onScreenshot: () {},
            onFit: (_) {},
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
    final button = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '本地和下载视频暂不支持特征标记',
      ),
    );
    expect(button.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.request = null;
  });
}

class _Picker extends FileSelectorPlatform {
  _Picker({this.directory});
  final String? directory;
  int calls = 0;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    calls++;
    return null;
  }

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async => directory;
}
