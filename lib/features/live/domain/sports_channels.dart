import 'channel_identity.dart';
import 'live_channel.dart';

const sportsChannelGroup = '体育直播';

final _sport = RegExp(
  r'体育|體育|运动赛事|運動賽事|奥林匹克|奧林匹克|'
  r'\b(?:sports?|motorsport|tennis|cricket|baseball|hockey|golf|racing|espn|sportstv)\b',
  caseSensitive: false,
);
final _football = RegExp(
  r'足球|英超|中超|欧冠|歐冠|西甲|德甲|意甲|'
  r'\b(?:soccer|fifa|uefa|laliga|bundesliga|futbol|fútbol|calcio)\b|'
  r'\bpremier league\b',
  caseSensitive: false,
);
final _footballWord = RegExp(r'\bfootball\b', caseSensitive: false);
final _otherFootball = RegExp(
  r'\b(?:nfl|cfb|afl)\b|\b(?:american|college|australian) football\b',
  caseSensitive: false,
);
final _basketball = RegExp(
  r'篮球|籃球|\b(?:basketball|nba|wnba|fiba|cba|euroleague)\b',
  caseSensitive: false,
);

/// Classify channel metadata and names. A sport tag describes programming,
/// while the programme guide remains the source of current and upcoming events.
Set<String> sportsChannelTags(LiveChannel channel) {
  final labels = [
    for (final entry in channel.entries) entry.name,
    ...channel.categories,
  ];
  final football = labels.any(
    (label) =>
        _football.hasMatch(label) ||
        (_footballWord.hasMatch(label) && !_otherFootball.hasMatch(label)),
  );
  final basketball = labels.any(_basketball.hasMatch);
  final sports =
      football ||
      basketball ||
      labels.any(_sport.hasMatch) ||
      channel.entries.any(
        (entry) =>
            {'CCTV5', 'CCTV5+', 'CCTV16'}.contains(cctvIdentity(entry.name)),
      );
  return {
    if (sports) sportsChannelGroup,
    if (football) '足球',
    if (basketball) '篮球',
  };
}
