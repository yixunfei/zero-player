import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/application_ownership.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a second process cannot own the same isolated data directory',
    () async {
      final root = await Directory.systemTemp.createTemp('zero-owner-');
      final process = await Process.start(
        Platform.isWindows ? 'dart.bat' : 'dart',
        ['run', 'test_support/ownership_probe.dart', root.path],
        runInShell: Platform.isWindows,
      );
      try {
        expect(
          await process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 30)),
          'locked',
        );
        await expectLater(
          ApplicationOwnership.acquire(root),
          throwsA(isA<ApplicationAlreadyRunning>()),
        );
        if (Platform.isWindows) {
          final cache = await Directory('${root.path}/segments').create();
          final part = await File(
            '${cache.path}/${'a' * 64}.part',
          ).writeAsString('in progress');
          const channel = MethodChannel('plugins.flutter.io/path_provider');
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async => root.path);
          try {
            await expectLater(
              AppServices.create(),
              throwsA(isA<ApplicationAlreadyRunning>()),
            );
            expect(await part.readAsString(), 'in progress');
            expect(
              await File('${root.path}/zero-player.sqlite').exists(),
              isFalse,
            );
          } finally {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null);
          }
        }
        process.stdin.writeln('release');
        expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
        final replacement = await ApplicationOwnership.acquire(root);
        await replacement.close();
        final crashed = await Process.start(
          Platform.isWindows ? 'dart.bat' : 'dart',
          ['run', 'test_support/ownership_probe.dart', root.path],
          runInShell: Platform.isWindows,
        );
        expect(
          await crashed.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 30)),
          'locked',
        );
        crashed.stdin.writeln('crash');
        expect(await crashed.exitCode.timeout(const Duration(seconds: 10)), 17);
        final afterCrash = await ApplicationOwnership.acquire(root);
        await afterCrash.close();
      } finally {
        process.kill();
        await root.delete(recursive: true);
      }
    },
  );
}
