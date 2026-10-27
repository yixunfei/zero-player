import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/catalog/domain/catalog_item.dart';
import 'package:zero_player/features/catalog/domain/work_identity.dart';
import 'package:zero_player/features/downloads/application/download_quota.dart';
import 'package:zero_player/media/hls/hls_manifest.dart';
import 'package:zero_player/media/hls/hls_quality.dart';

CatalogItem item(
  String source, {
  String title = '同一部剧',
  String year = '2026',
  String category = '国产剧',
}) => CatalogItem(
  sourceId: source,
  id: '1',
  title: title,
  year: year,
  category: category,
);

void main() {
  test(
    'source-specific category names merge, remakes and seasons stay separate',
    () {
      final groups = groupCatalogItems([
        item('a'),
        item('b', category: '电视剧'),
        item('c', year: '', category: ''),
        item('d', title: '同一部剧 第二季'),
        item('e', title: '同一部剧 导演剪辑版'),
      ]);
      expect(groups.length, 3);
      expect(groups.values.first.length, 3);
      final ambiguous = groupCatalogItems([
        item('a'),
        item('b', year: '2001'),
        item('c', year: ''),
      ]);
      expect(ambiguous.length, 3);
      expect(sameDownloadWork(item('a'), item('b', year: '2001')), isFalse);
      expect(sameDownloadWork(item('a'), item('b', year: '')), isFalse);
      expect(sameDownloadWork(item('a'), item('b', category: '电视剧')), isTrue);
    },
  );
  test('parallel tasks cannot reserve the same free space', () {
    final quota = DownloadQuota()..initialize({'saved': 30});
    quota.reserve('a', 40, 100);
    expect(() => quota.reserve('b', 40, 100), throwsA(isA<Exception>()));
    quota.reserve('b', 30, 100);
    quota.release('a');
    quota.reserve('b', 70, 100);
  });
  test('manual HLS quality retains external audio and subtitle renditions', () {
    final base = Uri.parse('https://media.test/master.m3u8');
    final manifest = HlsManifest.parse('''#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="中文",URI="audio.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360,AUDIO="audio"
low.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080,AUDIO="audio"
high.m3u8
''', base);
    final choices = hlsQualities(manifest);
    expect(choices.length, 2);
    final selected = selectHlsQuality(manifest, choices.last.uri);
    expect(selected.playlistUris, contains(base.resolve('audio.m3u8')));
    expect(selected.playlistUris, contains(base.resolve('high.m3u8')));
    expect(selected.playlistUris, isNot(contains(base.resolve('low.m3u8'))));
    expect(hlsQualities(selected).single.label, contains('1920x1080'));
  });
}
