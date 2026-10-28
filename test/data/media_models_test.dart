import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/live/data/m3u_parser.dart';
import 'package:zero_player/features/live/data/epg_parser.dart';
import 'package:zero_player/features/live/domain/channel_merge.dart';
import 'package:zero_player/media/hls/hls_manifest.dart';
import 'package:zero_player/media/hls/ad_filter.dart';

void main() {
  test('semantic matching preserves ambiguity and does not guess specials', () {
    final episodes = [
      Episode('第01集', Uri()),
      Episode('EP1', Uri()),
      Episode('番外1', Uri()),
    ];
    expect(matchingEpisodes('第一集', episodes), [0, 1]);
    expect(matchingEpisodes('SP1', episodes), isEmpty);
    expect(semanticEpisode('S02E03'), '2:3');
    expect(semanticEpisode('第十二集'), '1:12');
  });
  test('M3U groups duplicate channels and preserves scoped headers', () {
    final channels = parseM3u(
      '#EXTM3U\n#EXTINF:-1 tvg-id="a" group-title="News",A\n'
          '#EXTVLCOPT:http-user-agent=Fixture\nfirst.m3u8\n'
          '#EXTINF:-1 tvg-id="a" group-title="News",A\nsecond.m3u8\n',
      Uri.parse('https://example.org/list.m3u'),
      'list',
    );
    expect(channels, hasLength(2));
    final programme = mergeChannelAliases(channels).single;
    expect(
      programme.urls,
      unorderedEquals([
        Uri.parse('https://example.org/first.m3u8'),
        Uri.parse('https://example.org/second.m3u8'),
      ]),
    );
    expect(programme.headersFor(Uri.parse('https://example.org/first.m3u8')), {
      'User-Agent': 'Fixture',
    });
    expect(
      programme.headersFor(Uri.parse('https://example.org/second.m3u8')),
      isEmpty,
    );
    expect(
      () => parseM3u('#EXTM3U\n#EXT-X-TARGETDURATION:5\n', Uri(), 'a'),
      throwsFormatException,
    );
  });
  test('XMLTV UTC conversion and unsafe declarations', () {
    final items = parseEpg(
      '<tv><programme channel="a" start="20261026083000 +0800" stop="20261026093000 +0800"><title>News</title></programme></tv>',
    );
    expect(items.single.start, DateTime.utc(2026, 10, 26, 0, 30));
    expect(() => parseEpg('<!DOCTYPE tv><tv/>'), throwsFormatException);
  });
  test('paired ad cues map progress; discontinuity alone is preserved', () {
    final input = HlsManifest.parse(
      '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\na.ts\n'
      '#EXT-X-CUE-OUT:5\n#EXTINF:5,\nad.ts\n#EXT-X-CUE-IN\n#EXT-X-DISCONTINUITY\n#EXTINF:10,\nb.ts\n#EXT-X-ENDLIST\n',
      Uri.parse('https://example.org/v.m3u8'),
    );
    final filtered = filterDeclaredAds(input);
    expect(filtered.manifest.lines, isNot(contains('ad.ts')));
    expect(filtered.manifest.lines, contains('#EXT-X-DISCONTINUITY'));
    expect(
      filtered.timeline.toOriginal(const Duration(seconds: 10)),
      const Duration(seconds: 15),
    );
    expect(
      filtered.timeline.toProcessed(const Duration(seconds: 12)),
      const Duration(seconds: 10),
    );
    final unpaired = HlsManifest.parse(
      input.lines.where((l) => l != '#EXT-X-CUE-IN').join('\n'),
      input.baseUri,
    );
    expect(filterDeclaredAds(unpaired).manifest.lines, contains('ad.ts'));
  });
}
