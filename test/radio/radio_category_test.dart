import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/domain/live_channel.dart';
import 'package:zero_player/features/radio/domain/radio_category.dart';
import 'package:zero_player/features/radio/data/radio_repository.dart';

LiveChannel station(String name, {bool favorite = false}) => LiveChannel(
  id: name,
  listId: 'test',
  name: name,
  favorite: favorite,
  urls: [Uri.https('stream.test', '/$name')],
  group: 'China',
);

void main() {
  test(
    'TV audio is separated without misclassifying broadcasters radio services',
    () {
      for (final name in [
        'CCTV-13新闻伴音',
        'CCTV1',
        'CGTN - English',
        '凤凰卫视资讯台',
        '哈尔滨电视台 新闻综合频道',
        '厦门电视台-1',
      ]) {
        expect(
          radioCategory(station(name)),
          RadioCategory.television,
          reason: name,
        );
      }
      for (final name in [
        'CNR-1 中国之声',
        'CRI english',
        '辽宁广播电视台音乐广播',
        '十三师广播电视台FM106.5',
        '章丘广播电视台',
        'Nice Radio 永安广播电视台综合广播',
      ]) {
        expect(radioCategory(station(name)), RadioCategory.radio, reason: name);
      }
    },
  );
  test(
    'radio precedes even favorited TV, favorites lead within each category',
    () {
      final sorted = [
        station('CCTV-1', favorite: true),
        station('A广播'),
        station('Z广播', favorite: true),
      ]..sort(compareRadioStations);
      expect(sorted.map((s) => s.name), ['Z广播', 'A广播', 'CCTV-1']);
    },
  );
  test(
    'repository replaces television ranking while preserving favorite entries',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient(allowPrivateNetworks: true);
      final repo = RadioRepository(db, DocumentClient(http));
      addTearDown(() async {
        await repo.close();
        http.close();
        await db.close();
      });
      final radio = station('Z广播');
      await repo.favorite(radio, true);
      final sorted = await repo.withFavorites([
        station('CCTV-1'),
        station('A广播'),
        radio,
      ]);
      expect(sorted.map((s) => s.name), ['Z广播', 'A广播', 'CCTV-1']);
      expect(sorted.first.favorite, isTrue);
    },
  );
}
