import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/live/presentation/live_channel_tile.dart';

void main() {
  testWidgets('selection never plays; double click and Enter explicitly play', (
    tester,
  ) async {
    var selected = 0, played = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveChannelTile(
            channel: LiveChannel(
              id: 'one',
              listId: 'list',
              name: 'CCTV-1',
              urls: [Uri.parse('https://media.test/one.ts')],
            ),
            selected: true,
            onSelect: () => selected++,
            onPlay: () => played++,
            onAction: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('live-focus-one'));
    await tester.tap(tile);
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
    expect(selected, greaterThan(0));
    expect(played, 0);
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(played, 1);
    tester.widget<InkWell>(tile).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(played, 2);
    await tester.tap(find.byTooltip('频道操作'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('停用频道'));
    await tester.pumpAndSettle();
    expect(played, 2);
  });
}
