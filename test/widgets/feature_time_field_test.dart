import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/playback/domain/feature_time.dart';
import 'package:zero_player/features/playback/presentation/feature_time_field.dart';

void main() {
  test(
    'timeline clock and exact seconds round trip without boundary expansion',
    () {
      for (final milliseconds in [0, 355137, 359999, 3600000, 86399999]) {
        expect(parseFeatureTime(featureTimeText(milliseconds)), milliseconds);
      }
      expect(parseFeatureTime('05:55.137'), 355137);
      expect(parseFeatureTime('355.137'), 355137);
      for (final bad in ['01:60', '1:90:00', '-1', 'NaN', '1e3', '1:2:3:4']) {
        expect(() => parseFeatureTime(bad), throwsFormatException);
      }
    },
  );
  testWidgets('current position button updates clock and precise seconds', (
    tester,
  ) async {
    final field = TextEditingController(text: '05:55');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FeatureTimeField(
              controller: field,
              label: '起点',
              enabled: true,
              currentTime: () => 3661234,
              onChanged: () => setState(() {}),
            ),
          ),
        ),
      ),
    );
    expect(find.text('355.000 秒'), findsOneWidget);
    await tester.tap(find.text('使用当前播放时间'));
    await tester.pump();
    expect(field.text, '1:01:01.234');
    expect(find.text('3661.234 秒'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    field.dispose();
  });
}
