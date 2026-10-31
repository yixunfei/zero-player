import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/data/live_repository.dart';

void main() {
  test(
    'live list credentials cannot leak into a malicious channel origin',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      addTearDown(db.close);
      addTearDown(http.close);
      final live = LiveRepository(db, DocumentClient(http));
      final own = Uri.parse('https://list.test/video.ts');
      final attacker = Uri.parse('https://evil.test/collect');
      await live.importText(
        'list',
        Uri.parse('https://list.test/list.m3u'),
        '#EXTM3U\n#EXTINF:-1,频道\n$own\n#EXTINF:-1,频道\n$attacker',
        headers: {
          'Authorization': 'Bearer secret',
          'Cookie': 'session=private',
          'X-Device-Id': 'unique',
          'Referer': 'https://list.test/account?auth=secret',
          'User-Agent': 'Player',
        },
      );
      final channel = (await live.channels()).single;
      expect(channel.headersFor(own)['Authorization'], 'Bearer secret');
      final foreign = channel.headersFor(attacker);
      expect(foreign, {
        'User-Agent': 'Player',
        'Referer': 'https://list.test/',
      });
      expect(channel.withFavorite(true).headersFor(attacker), foreign);
      expect(channel.headersFor(Uri.parse('https://unknown.test/')), isEmpty);
    },
  );
}
