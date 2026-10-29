import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/sources/data/source_repository.dart';
import 'package:zero_player/features/sources/presentation/channel_favorite_action.dart';

void main() {
  testWidgets(
    'detail favorite persists and follows external preference changes',
    (tester) async {
      final db = AppDatabase.memory();
      final sources = SourceRepository(db);
      final id = await sources.saveManual(
        'channel',
        Uri.parse('https://example.org/api'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChannelFavoriteAction(sourceId: id, repository: sources),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('收藏该渠道'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
      expect((await sources.find(id))!.favorite, isTrue);
      expect(find.text('已收藏渠道'), findsOneWidget);
      await sources.favorite(id, false);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(find.text('收藏该渠道'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await db.close();
    },
  );
}
