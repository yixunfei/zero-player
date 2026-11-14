import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/features/books/data/book_import.dart';
import 'package:zero_player/features/books/data/legado/legado_worker.dart';
import 'package:zero_player/features/books/domain/book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _importTest();
  _imageRuleTest();
  _verifiedSourceTest();
}

void _importTest() {
  test('comic source imports with its own kind and preserves media hosts', () {
    final source = parseBookSourceRecord({
      'bookSourceName': '漫画样本',
      'bookSourceUrl': 'https://comic.example.test',
      'bookSourceType': 2,
      'searchUrl': '/search?key={{key}}',
      'mediaHosts': ['images.example.test'],
      'ruleSearch': {
        'bookList': '.book',
        'name': '.name@text',
        'bookUrl': 'a@href',
      },
      'ruleToc': {
        'chapterList': '.chapter',
        'chapterName': 'a@text',
        'chapterUrl': 'a@href',
      },
      'ruleContent': {'content': '.pages'},
    });
    expect(source.kind, BookKind.comic);
    expect(source.mediaHosts, contains('images.example.test'));
    expect(BookSource.fromJson(source.toJson()).kind, BookKind.comic);
  });
}

void _imageRuleTest() {
  test('comic content rule extracts lazy image addresses in order', () async {
    final source = parseBookSourceRecord({
      'bookSourceName': '漫画样本',
      'bookSourceUrl': 'https://comic.example.test',
      'bookSourceType': 2,
      'searchUrl': '/search?key={{key}}',
      'ruleSearch': {
        'bookList': '.book',
        'name': '.name@text',
        'bookUrl': 'a@href',
      },
      'ruleToc': {
        'chapterList': '.chapter',
        'chapterName': 'a@text',
        'chapterUrl': 'a@href',
      },
      'ruleContent': {'content': '.pages'},
    });
    final result = await runLegadoJob(
      LegadoJob(
        source,
        Uri.parse('https://comic.example.test/chapter'),
        LegadoOperation.images,
        input:
            '<div class="pages"><img data-src="/1.jpg"><img src="/2.jpg"><img src="/1.jpg"></div>',
      ),
      CancellationToken(),
    );
    expect(result.links, ['/1.jpg', '/2.jpg']);
  });
}

void _verifiedSourceTest() {
  test(
    'verified Manman comic uses current search and declared image CDN',
    () async {
      final source = parseBookSourceRecord({
        'bookSourceName': '🎨漫漫漫画',
        'bookSourceUrl': 'https://www.manmanapp.com',
        'bookSourceType': 2,
        'searchUrl': 'https://www.manmanapp.com/search/word-{{key}}.html',
        'ruleSearch': {
          'bookList': 'class.classification',
          'name': 'class.title@text',
          'bookUrl': 'tag.a.0@href',
        },
        'ruleToc': {
          'chapterList': r'$.data',
          'chapterName': r'$.title',
          'chapterUrl': r'https://www.manmanapp.com/comic/detail-{{$.id}}.html',
        },
        'ruleContent': {'content': 'class.man_img@html'},
      });
      expect(source.kind, BookKind.comic);
      expect(
        source.legado!.search,
        'https://www.manmanapp.com/search/index.html?keyword={{key}}',
      );
      expect(source.mediaHosts, contains('images.tmanga.com'));
      final result = await runLegadoJob(
        LegadoJob(
          source,
          Uri.parse('https://www.manmanapp.com/comic/detail-1572470.html'),
          LegadoOperation.images,
          input:
              '<div class="man_img"><img '
              'src="https://images.tmanga.com/comic/small/1.jpg-cs1080"></div>',
        ),
        CancellationToken(),
      );
      expect(result.links, [
        'https://images.tmanga.com/comic/small/1.jpg-cs1080',
      ]);
      expect(
        source
            .resolve(
              Uri.parse('https://www.manmanapp.com/comic/detail-1572470.html'),
              result.links.single,
              media: true,
            )
            .host,
        'images.tmanga.com',
      );
    },
  );
}
