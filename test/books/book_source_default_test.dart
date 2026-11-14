import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/data/book_store.dart';
import 'package:zero_player/features/books/domain/book.dart';

void main() {
  test('WAF-limited builtin stays listed and can be manually enabled', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final store = BookStore(db);
    final source = BookSource.fromJson({
      'name': '受限来源',
      'kind': 'text',
      'format': 'featured',
      'url': 'https://fixture.test/',
      'defaultEnabled': false,
      'featured': [
        {'title': '样本', 'url': '/book'},
      ],
      'rules': {
        'chapters': 'a',
        'chapterTitle': '@text',
        'chapterUrl': '@href',
        'content': 'p@text',
      },
    }, builtin: true);
    expect((await store.sources([source])).single.enabled, isFalse);
    expect(await store.sources([source], enabledOnly: true), isEmpty);
    await store.saveSource(source, {'enabled': true});
    expect((await store.sources([source], enabledOnly: true)).single.source.id, source.id);
    expect(BookSource.fromJson(source.toJson()).defaultEnabled, isFalse);
  });
}
