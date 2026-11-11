import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/live/presentation/live_browser.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/live/presentation/live_channel_tile.dart';

void main() {
  _sourceControlsTest();
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
    await tester.tap(find.text('停用整个频道'));
    await tester.pumpAndSettle();
    expect(played, 2);
  });
}

void _sourceControlsTest() {
  testWidgets('channel and source confirmations identify their scope', (
    tester,
  ) async {
    const a = LiveChannel(
      id: 'a',
      listId: 'list-a',
      listName: '渠道甲',
      name: 'CCTV-1 综合',
      urls: [],
    );
    const b = LiveChannel(
      id: 'b',
      listId: 'list-b',
      listName: '渠道乙',
      name: 'CCTV-1 综合',
      urls: [],
    );
    const merged = LiveChannel(
      id: 'merged',
      listId: 'list-a',
      name: 'CCTV-1 综合',
      urls: [],
      members: [a, b],
    );
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var whole = 0;
    List<LiveChannel>? disabled;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveBrowser(
            channels: const [merged],
            group: '全部',
            query: '',
            controller: controller,
            onGroup: (_) {},
            onSelect: (_) {},
            onPlay: (_) {},
            onFavorite: (_) {},
            onToggle: (_) => whole++,
            onDisableSource: (entries) async {
              disabled = entries;
              return true;
            },
            onEpg: (_) {},
            onProbe: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('停用整个频道'));
    await tester.pumpAndSettle();
    expect(find.text('停用整个频道「CCTV-1 综合」'), findsOneWidget);
    expect(find.textContaining('全部 2 个渠道'), findsOneWidget);
    expect(whole, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(whole, 0);
    await tester.tap(find.byTooltip('停用整个频道'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '停用整个频道'));
    await tester.pumpAndSettle();
    expect(whole, 1);

    await tester.tap(find.byTooltip('频道详情'));
    await tester.pumpAndSettle();
    final source = find
        .ancestor(of: find.text('渠道甲'), matching: find.byType(Column))
        .first;
    final disable = find.descendant(of: source, matching: find.text('停用此渠道'));
    await tester.ensureVisible(disable);
    await tester.tap(disable);
    await tester.pumpAndSettle();
    expect(find.text('停用渠道「渠道甲」'), findsOneWidget);
    expect(disabled, isNull);
    await tester.tap(find.widgetWithText(FilledButton, '停用此渠道'));
    await tester.pumpAndSettle();
    expect(disabled, [a]);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
