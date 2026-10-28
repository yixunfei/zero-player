import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_theme.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/radio/application/radio_controller.dart';
import 'package:zero_player/features/radio/presentation/radio_player_controls.dart';
import 'package:zero_player/features/radio/presentation/radio_mini_player.dart';

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets('radio folds and expands at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller =
          RadioController(
              () => throw StateError('Folding must not create another player'),
            )
            ..selected = LiveChannel(
              id: 'test',
              listId: 'radio',
              name: '测试广播',
              urls: [Uri.https('radio.test', '/stream')],
            );
      addTearDown(controller.dispose);
      var expanded = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => expanded
                  ? RadioPlayerControls(
                      controller: controller,
                      onCollapse: () => setState(() => expanded = false),
                    )
                  : RadioMiniPlayer(
                      controller: controller,
                      onExpand: () => setState(() => expanded = true),
                    ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('收起广播播放器'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
      expect(controller.selected!.id, 'test');
      await tester.tap(find.byTooltip('展开广播播放器'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
      expect(controller.selected!.id, 'test');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
      'radio controls remain usable at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller =
            RadioController(
                () => throw StateError('Layout test does not open a player'),
              )
              ..selected = LiveChannel(
                id: 'test',
                listId: 'radio',
                name: '测试广播',
                urls: [
                  Uri.parse('https://example.com/a.mp3'),
                  Uri.parse('https://example.com/b.mp3'),
                ],
              );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.dark, false, 'cinema'),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: RadioPlayerControls(controller: controller),
              ),
            ),
          ),
        );
        final slider = tester.widget<Slider>(find.byType(Slider));
        expect(slider.value, 80);
        expect(slider.max, 100);
        expect(find.byTooltip('停止广播').hitTestable(), findsOneWidget);
        expect(find.byTooltip('切换广播线路').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}
