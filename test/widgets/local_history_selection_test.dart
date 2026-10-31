import 'dart:io';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/playback/application/local_video.dart';
import 'package:zero_player/features/playback/application/playback_controller.dart';
import 'package:zero_player/features/playback/presentation/local_video_page.dart';

void main() => _historySelectionTests();

void _historySelectionTests() {
  for (final missing in [false, true]) {
    _historySelectionTest(missing);
  }
}

void _historySelectionTest(bool missing) {
  testWidgets(
    'history selection separates new files and relocation: missing=$missing',
    (tester) async {
      final root = (await tester.runAsync(_temporaryRoot))!;
      final services = (await tester.runAsync(
        () async => AppServices.scoped(root, AppDatabase.memory()),
      ))!;
      final previousPicker = FileSelectorPlatform.instance;
      late String oldId;
      late File replacement;
      await tester.runAsync(() async {
        await services.settings.load();
        await services.supervision.load();
        final old = await File('${root.path}/old.mp4').writeAsBytes([1]);
        replacement = await File('${root.path}/new.mp4').writeAsBytes([2]);
        final request = await LocalVideo.open(services, old.path);
        oldId = request.item.id;
        await services.history.save(
          request.item,
          request.item.lines.single,
          request.item.lines.single.episodes.single,
          const Duration(seconds: 20),
          const Duration(seconds: 100),
        );
        request.offline!.close();
        if (missing) await old.delete();
      });
      FileSelectorPlatform.instance = _Picker(replacement.path);
      final requests = <PlaybackRequest>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: LocalVideoPage(services: services, id: oldId),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (context, state) {
              final request = state.extra! as PlaybackRequest;
              if (!requests.contains(request)) requests.add(request);
              return Scaffold(
                body: TextButton(
                  onPressed: () {
                    request.offline!.close();
                    context.pop();
                  },
                  child: const Text('返回测试'),
                ),
              );
            },
          ),
        ],
      );
      Future<void> settle() async {
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await settle();
        if (!missing) {
          expect(requests.single.item.id, oldId);
          await tester.tap(find.text('返回测试'));
          await settle();
        } else {
          expect(find.text('重新定位原记录（保留进度）'), findsOneWidget);
        }
        await tester.tap(find.text(missing ? '重新定位原记录（保留进度）' : '选择视频文件'));
        await settle();
        final opened = requests.last;
        expect(opened.item.id, missing ? oldId : isNot(oldId));
        expect(
          opened.position,
          missing ? const Duration(seconds: 20) : Duration.zero,
        );
      } finally {
        for (final request in requests) {
          request.offline!.close();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        FileSelectorPlatform.instance = previousPicker;
        await tester.runAsync(() async {
          await services.close();
          await root.delete(recursive: true);
        });
      }
    },
  );
}

class _Picker extends FileSelectorPlatform {
  _Picker(this.path);
  final String path;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile(path);
}

Future<Directory> _temporaryRoot() =>
    Directory.systemTemp.createTemp('history-select-');
