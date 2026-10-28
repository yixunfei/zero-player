import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/discovery/data/release_calendar.dart';
import 'package:zero_player/features/settings/application/settings_controller.dart';
import '../../test_support/http_test_server.dart';

const _page =
    '<table class="coming_list"><tbody>'
    '<tr><td>10月30日</td><td><a href="https://movie.douban.com/subject/123/">新片 &amp; 重映</a></td><td>剧情</td><td>中国大陆</td></tr>'
    '<tr><td>2027年02月</td><td><a href="https://movie.douban.com/subject/456/">待定档期</a></td><td>动画</td><td>日本</td></tr>'
    '<tr><td>11月01日</td><td><a href="https://untrusted.test/subject/789/">广告</a></td><td>广告</td><td>未知</td></tr>'
    '</tbody></table>';

void main() {
  test(
    'calendar preserves source date precision and only accepts source subject links',
    () {
      final items = parseReleaseCalendar(_page);
      expect(items, hasLength(2));
      expect(items.first.title, '新片 & 重映');
      expect(items.first.date, '10月30日');
      expect(items.last.date, '2027年02月');
      expect(
        () => parseReleaseCalendar('<html>verify</html>'),
        throwsFormatException,
      );
    },
  );
  test(
    'failed refresh retains last successful calendar without rewriting its timestamp',
    () async {
      var failed = false;
      final server = await HttpTestServer.start((request) {
        if (failed) {
          request.response.statusCode = 403;
          return;
        }
        request.response.headers.contentType = ContentType(
          'text',
          'html',
          charset: 'utf-8',
        );
        request.response.write(_page);
      });
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final db = AppDatabase.memory();
      addTearDown(() async {
        http.close();
        await server.close();
        await db.close();
      });
      final repository = ReleaseCalendarRepository(
        DocumentClient(http),
        db,
        endpoint: server.baseUri,
      );
      final first = await repository.load(cancellation: CancellationToken());
      failed = true;
      final second = await repository.load(
        refresh: true,
        cancellation: CancellationToken(),
      );
      expect(second.cached, isTrue);
      expect(
        second.updatedAt.millisecondsSinceEpoch,
        first.updatedAt.millisecondsSinceEpoch,
      );
      expect(
        second.items.map((item) => item.title),
        first.items.map((item) => item.title),
      );
      final token = CancellationToken()..cancel();
      await expectLater(
        repository.load(cancellation: token),
        throwsA(isA<RequestCancelled>()),
      );
    },
  );
  test(
    'removed recommendation settings normalize and persist without losing other settings',
    () async {
      final db = AppDatabase.memory();
      final settings = SettingsController(db);
      addTearDown(() async {
        await settings.close();
        await db.close();
      });
      await db.write('INSERT INTO settings VALUES(?,?)', [
        'recommendation',
        '"bangumi"',
      ]);
      await settings.load();
      expect(settings.value.recommendation, 'douban');
      expect(
        (await db.rows(
          "SELECT value FROM settings WHERE key='recommendation'",
        )).single['value'],
        '"douban"',
      );
    },
  );
}
