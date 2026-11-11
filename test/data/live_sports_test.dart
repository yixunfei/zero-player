import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/live/domain/channel_order.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/live/domain/live_health.dart';
import 'package:zero_player/features/live/domain/sports_channels.dart';
import 'package:zero_player/features/live/presentation/live_channel_filters.dart';

LiveChannel _channel(String name, {String group = '', bool enabled = true}) =>
    LiveChannel(
      id: name,
      listId: 'test',
      name: name,
      group: group,
      urls: [Uri.parse('https://tv.example.test/live.m3u8')],
      health: LiveHealth(enabled: enabled),
    );

void main() {
  test('sports is an additional group for enabled channels', () {
    final cctv = _channel('CCTV-5+ 体育赛事');
    expect(matchesChannel(cctv, sportsChannelGroup, ''), isTrue);
    expect(matchesChannel(cctv, '央视', ''), isTrue);
    expect(matchesChannel(_channel('CCTV-16'), sportsChannelGroup, ''), isTrue);
    expect(
      matchesChannel(_channel('CCTV-15 音乐'), sportsChannelGroup, ''),
      isFalse,
    );
    final disabled = _channel('地方体育', enabled: false);
    expect(matchesChannel(disabled, sportsChannelGroup, ''), isFalse);
    expect(matchesChannel(disabled, '已停用', ''), isTrue);
  });

  test('sports tags support search and football or basketball filters', () {
    final football = _channel('FIFA+');
    final basketball = _channel('NBA TV');
    final generic = _channel('Channel 1', group: 'Sports');
    expect(matchesChannel(football, sportsChannelGroup, '足球'), isTrue);
    expect(matchesChannel(basketball, sportsChannelGroup, '篮球'), isTrue);
    expect(matchesChannel(generic, sportsChannelGroup, ''), isTrue);
    expect(const LiveChannelFilter(category: '足球').matches(football), isTrue);
    expect(
      const LiveChannelFilter(category: '足球').matches(basketball),
      isFalse,
    );
    expect(const LiveChannelFilter(category: '足球').matches(generic), isFalse);
    expect(
      sportsChannelTags(_channel('NFL American Football', group: 'Sports')),
      {sportsChannelGroup},
    );
  });
}
