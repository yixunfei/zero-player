import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_theme.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/radio/application/radio_controller.dart';
import 'package:zero_player/features/radio/presentation/radio_player_controls.dart';

void main() {
  for (final width in [320.0, 1280.0]) {
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
