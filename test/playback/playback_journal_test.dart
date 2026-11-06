import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/playback/application/playback_journal.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('playback-journal-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'unclean evidence survives a later normal session and a new instance',
    () async {
      var journal = PlaybackJournal(root);
      await journal.initialize();
      await journal.write('memory 300; native warning');
      journal = PlaybackJournal(root);
      await journal.initialize();
      expect(journal.previousReport, contains('native warning'));
      await journal.write('next session closed', closed: true);
      journal = PlaybackJournal(root);
      await journal.initialize();
      expect(journal.previousReport, contains('native warning'));
      await journal.write('normal', closed: true);
      expect(
        jsonDecode(await journal.current.readAsString())['status'],
        'closed',
      );
    },
  );

  test(
    'snapshots stay bounded and sequential under overlapping writes',
    () async {
      final journal = PlaybackJournal(root);
      await journal.initialize();
      await Future.wait([
        journal.write('large ${'内容' * 30000}'),
        journal.write('last', closed: true),
      ]);
      expect(await journal.current.length(), lessThan(PlaybackJournal.limit));
      expect(
        jsonDecode(await journal.current.readAsString())['report'],
        'last',
      );
      expect(await File('${journal.current.path}.tmp').exists(), isFalse);
    },
  );

  test('corrupt prior snapshot cannot prevent a new diagnostic', () async {
    final journal = PlaybackJournal(root);
    await journal.current.parent.create(recursive: true);
    await journal.current.writeAsString('interrupted JSON');
    await journal.initialize();
    await journal.write('new');
    expect(jsonDecode(await journal.current.readAsString())['report'], 'new');
  });
}
