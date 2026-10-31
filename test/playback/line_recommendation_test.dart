import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/media/network/media_probe.dart';
import 'package:zero_player/features/playback/application/line_recommendation.dart';

void main() {
  ProbeResult result(int ms, String? resolution) => ProbeResult(
    Duration(milliseconds: ms),
    1024,
    const Duration(seconds: 1),
    resolution,
  );
  test('known low resolution does not win only because it responds first', () {
    expect(
      compareLineResponses(result(5, '640x360'), result(100, '1920x1080')),
      greaterThan(0),
    );
    expect(
      compareLineResponses(result(5, null), result(100, null)),
      lessThan(0),
    );
    expect(
      compareLineResponses(result(5, '1280x720'), result(100, '1920x1080')),
      lessThan(0),
    );
  });
}
