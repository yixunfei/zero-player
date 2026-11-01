import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/music/domain/music_track.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  for (final provider in ['lxHelloWorld', 'lxHyw', 'musicBox']) {
    testWidgets(
      'native $provider resolves and decodes public sample',
      (tester) => _exercise(tester, provider),
      skip: !const bool.fromEnvironment('RUN_MUSIC_ONLINE'),
    );
  }
}

Future<void> _exercise(WidgetTester tester, String provider) async {
  final root = await Directory.systemTemp.createTemp('lx-native-');
  final services = AppServices.scoped(root, AppDatabase.memory());
  try {
    await services.settings.load();
    await services.supervision.load();
    await tester.pumpWidget(const SizedBox.shrink());
    await services.musicPlayer.select([
      MusicTrack(
        id: '1859245776',
        title: '公开音乐样本',
        artist: '',
        url: Uri.parse('https://music.163.com'),
        fetchedAt: DateTime.now(),
        provider: provider,
        downloadable: false,
      ),
    ], 0);
    final watch = Stopwatch()..start();
    while (services.musicPlayer.snapshot.position <
            const Duration(seconds: 1) &&
        watch.elapsed < const Duration(seconds: 30)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(services.musicPlayer.error, isNull);
    expect(services.musicPlayer.playing, isTrue);
    expect(services.musicPlayer.snapshot.position, greaterThan(Duration.zero));
    debugPrint(
      'LX_NATIVE_DECODE_OK $provider position=${services.musicPlayer.snapshot.position}',
    );
  } finally {
    await services.close();
    await root.delete(recursive: true);
  }
}
