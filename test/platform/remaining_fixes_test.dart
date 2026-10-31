import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/core/persistence/application_ownership.dart';
import 'package:zero_player/core/persistence/local_open_channel.dart';
import 'package:zero_player/features/playback/application/local_video.dart';
import 'package:zero_player/features/playback/application/player_exit.dart';
import 'package:zero_player/features/playback/presentation/local_video_page.dart';

void main() {
  _case0();
  _case1();
  _case2();
  _case3();
}

void _case0() {
  test('exit navigates after both cleanup steps fail', () async {
    final events = <String>[];
    await finishPlayerExit(
      close: () async {
        events.add('close');
        throw StateError('engine failed');
      },
      restore: () async {
        events.add('restore');
        throw StateError('window failed');
      },
      navigate: () => events.add('navigate'),
      report: (_, _) => events.add('report'),
    );
    expect(events, ['close', 'restore', 'navigate', 'report', 'report']);
  });
}

void _case1() {
  test(
    'document identity preserves resume across different cache copies',
    () async {
      final root = await Directory.systemTemp.createTemp('document-resume-');
      final services = AppServices.scoped(root, AppDatabase.memory());
      try {
        await services.settings.load();
        await services.supervision.load();
        final one = await File('${root.path}/one.mp4').writeAsBytes([1, 2, 3]);
        final two = await File('${root.path}/two.mp4').writeAsBytes([1, 2, 3]);
        final first = await LocalVideo.open(
          services,
          one.path,
          documentIdentity: 'document-one',
        );
        await services.history.save(
          first.item,
          first.item.lines.single,
          first.item.lines.single.episodes.single,
          const Duration(seconds: 12),
          const Duration(seconds: 60),
        );
        first.offline!.close();
        final second = await LocalVideo.open(
          services,
          two.path,
          documentIdentity: 'document-one',
        );
        expect(second.item.id, first.item.id);
        expect(second.position, const Duration(seconds: 12));
        second.offline!.close();
        final other = await LocalVideo.open(
          services,
          two.path,
          documentIdentity: 'document-two',
        );
        expect(other.item.id, isNot(first.item.id));
        expect(other.position, Duration.zero);
        other.offline!.close();
      } finally {
        await services.close();
        await root.delete(recursive: true);
      }
    },
  );
}

void _case2() {
  testWidgets('local page scrolls in landscape with enlarged text', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('local-layout-'),
    ))!;
    final services = (await tester.runAsync(() async {
      final value = AppServices.scoped(root, AppDatabase.memory());
      await value.settings.load();
      return value;
    }))!;
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(),
            bottomNavigationBar: const SizedBox(height: 64),
            body: LocalVideoPage(services: services),
          ),
        ),
      );
      await tester.scrollUntilVisible(find.text('选择视频文件'), 100);
      await tester.ensureVisible(find.text('选择视频文件'));
      await tester.pumpAndSettle();
      expect(find.text('选择视频文件').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      await tester.runAsync(() async {
        await services.close();
        await root.delete(recursive: true);
      });
    }
  });
}

void _case3() {
  test(
    'second isolated process forwards video while owner retains its lock',
    () async {
      final root = await Directory.systemTemp.createTemp('forward-owner-');
      final owner = await ApplicationOwnership.acquire(root);
      try {
        final next = owner.channel.requests.first;
        final path = '${root.path}${Platform.pathSeparator}中文 视频.mp4';
        final result = await Process.run(
          Platform.isWindows ? 'dart.bat' : 'dart',
          ['run', 'test_support/open_forward_probe.dart', root.path, path],
          runInShell: Platform.isWindows,
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(await next.timeout(const Duration(seconds: 3)), path);
        await expectLater(
          ApplicationOwnership.acquire(root),
          throwsA(isA<ApplicationAlreadyRunning>()),
        );
        expect(
          await LocalOpenChannel.forward(root, 'https://example.com/video.mp4'),
          isFalse,
        );
        final endpoint = File('${root.path}/.open-endpoint.json');
        final data = await endpoint.readAsString();
        final port = int.parse(RegExp(r'"port":(\d+)').firstMatch(data)![1]!);
        final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
        socket.write(
          'POST /open HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nContent-Length: 0\r\nConnection: close\r\n\r\n',
        );
        await socket.flush();
        final response = await socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();
        expect(response, startsWith('HTTP/1.1 403'));
        socket.destroy();
        await owner.channel.close();
        expect(await LocalOpenChannel.forward(root, path), isFalse);
        await expectLater(
          ApplicationOwnership.acquire(root),
          throwsA(isA<ApplicationAlreadyRunning>()),
        );
      } finally {
        await owner.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
