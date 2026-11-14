import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_services.dart';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/books/data/qidian_catalog.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/presentation/book_discovery_view.dart';

const _home = 'https://www.qidian.com/';
const _rank = '${_home}rank/yuepiao/';
const _next = '${_rank}page2/';
const _work = '${_home}book/12345/';

String _rows(String title, {String? next, int id = 12345}) =>
    '<ul class="book-img-text"><li><h2><a href="/book/$id/">$title</a></h2></li></ul>'
    '${next == null ? '' : '<a rel="next" href="$next">下一页</a>'}';

List<int> _html(String address, String body) => utf8.encode(
  '<!DOCTYPE html>\n<!-- saved from url=(${address.length})$address -->\n'
  '<html><head><meta charset="utf-8"></head><body>$body</body></html>',
);

List<int> _archive(String address, String body) {
  final encoded = utf8
      .encode(body)
      .map((byte) => '=${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}')
      .join();
  return ascii.encode(
    [
      'From: <Saved by Blink>',
      'Snapshot-Content-Location: $address',
      'MIME-Version: 1.0',
      'Content-Type: multipart/related;',
      '\tboundary="browser-boundary"',
      '',
      '--browser-boundary',
      'Content-Type: text/html; charset=UTF-8',
      'Content-Location: $address',
      'Content-Transfer-Encoding: quoted-printable',
      '',
      '${encoded.substring(0, 45)}=',
      encoded.substring(45),
      '--browser-boundary',
      'Content-Type: image/png',
      '',
      'unused',
      '--browser-boundary--',
      '',
    ].join('\r\n'),
  );
}

Future<(AppServices, Directory)> _openServices() async {
  final root = await Directory.systemTemp.createTemp('qidian-browser-');
  final services = AppServices.scoped(root, AppDatabase.memory());
  await services.settings.load();
  await services.supervision.load();
  return (services, root);
}

Future<AppServices> _services() async {
  final (services, root) = await _openServices();
  addTearDown(() => _closeServices(services, root));
  return services;
}

Future<void> _closeServices(AppServices services, Directory root) async {
  await services.close();
  await root.delete(recursive: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _listings();
  _details();
  _discovery();
}

void _listings() {
  test(
    'imports only the selected ranking page and caches its first page',
    () async {
      final services = await _services();
      final catalog = services.books.qidian;
      final token = CancellationToken();
      final first = await catalog.importListing(
        '${_rank}page1/',
        _html(_rank, _rows('首榜样本', next: _next)),
        token,
        firstPage: true,
      );
      expect(first.page.books.single.title, '首榜样本');
      expect(first.page.next.toString(), _next);
      final selectors = [
        _html(_rank, _rows('错误页码')),
        _html('${_home}rank/recom/', _rows('错误榜单')),
        _html('https://m.qidian.com/rank/yuepiao/page2/', _rows('错误主机')),
        _html(_next, '<script src="/example/probe.js?v=1"></script>'),
      ];
      for (final bytes in selectors) {
        await expectLater(
          catalog.importListing(_next, bytes, token, firstPage: false),
          throwsA(isA<FormatException>()),
        );
      }
      final second = await catalog.importListing(
        _next,
        _archive(_next, _rows('次页样本', id: 12346)),
        token,
        firstPage: false,
      );
      expect(second.page.books.single.title, '次页样本');
      final rows = await services.db.rows(
        'SELECT payload FROM recommendation_cache WHERE provider LIKE ?',
        ['qidian:%'],
      );
      final payload = jsonDecode(rows.single['payload'] as String) as Map;
      expect(payload['imported'], isTrue);
      expect(payload['next'], _next);
      expect((payload['books'] as List).single['title'], '首榜样本');
    },
  );

  test('listing import checks query filters and cancellation', () async {
    final catalog = (await _services()).books.qidian;
    const path = '${_home}all/';
    final bytes = _html('$path?page=2&chanId=21', _rows('玄幻样本'));
    Future<QidianListing> load(String query, CancellationToken token) =>
        catalog.importListing('$path?$query', bytes, token, firstPage: false);
    expect(
      (await load(
        'chanId=21&page=2',
        CancellationToken(),
      )).page.books.single.title,
      '玄幻样本',
    );
    final first = await catalog.importListing(
      '$path?chanId=21&siteid=1&page=1',
      _html('${path}chanId21/', _rows('同栏目首页')),
      CancellationToken(),
      firstPage: true,
    );
    expect(first.page.books.single.title, '同栏目首页');
    await expectLater(
      load('chanId=21&page=1', CancellationToken()),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      load('chanId=21&page=2', CancellationToken()..cancel()),
      throwsA(isA<RequestCancelled>()),
    );
  });
}

void _details() {
  test(
    'imports work facts from a saved HTML with a canonical work URL',
    () async {
      final catalog = (await _services()).books.qidian;
      final token = CancellationToken();
      final book = Book(
        qidianRecommendationId,
        BookKind.text,
        '样本',
        '',
        Uri.parse(_work),
      );
      final bytes = utf8.encode('''
      <!doctype html><html><head>
      <link rel="canonical" href="$_work">
      <meta property="og:novel:book_name" content="样本">
      <meta property="og:novel:author" content="样本作者">
      </head><body><div class="book-info"><p>
      26万字 90总推荐 0周推荐</p></div></body></html>
    ''');
      await expectLater(
        catalog.importDetails(
          book,
          _html('${_home}book/12346/', '<h1>其他作品</h1>'),
          token,
        ),
        throwsA(isA<FormatException>()),
      );
      final info = await catalog.importDetails(book, bytes, token);
      expect(info.author, '样本作者');
      expect(info.words, '26万');
      expect(info.totalRecommendations, '90');
      expect(info.weeklyRecommendations, '0');
      expect(await catalog.details(book, token), info);
    },
  );
}

void _discovery() {
  testWidgets(
    'restores discovery via the file picker and opens channel search',
    (tester) async {
      final (services, root) = (await tester.runAsync(_openServices))!;
      addTearDown(() => tester.runAsync(() => _closeServices(services, root)));
      final previous = FileSelectorPlatform.instance;
      final picker = _SavedPagePicker(
        _html(_home, _rows('恢复的作品', next: _next)),
      );
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = previous);
      (String, bool)? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookDiscoveryView(
              repository: services.books,
              kind: BookKind.text,
              sources: const [],
              active: true,
              onOpen: (book, {bool direct = false}) =>
                  opened = (book.title, direct),
              onSearch: (_, _, _) {},
              onSourceFavorite: (_, _) {},
              onManage: () {},
            ),
          ),
        ),
      );
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(finder, findsWidgets);
      }

      final import = find.text('导入浏览器网页');
      await waitFor(import);
      await tester.tap(import);
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择网页文件'));
      final work = find.text('恢复的作品');
      await waitFor(work);
      expect(find.textContaining('导入的起点书单'), findsOneWidget);
      await tester.ensureVisible(work.last);
      await tester.pumpAndSettle();
      await tester.tap(work.last);
      expect(opened, ('恢复的作品', false));

      picker.bytes = _archive(_next, _rows('恢复的下页作品', id: 12346));
      final next = find.text('导入下一页网页');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('选择网页文件'));
      await waitFor(find.text('恢复的下页作品'));
      expect(find.text('恢复的作品'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

final class _SavedPagePicker extends FileSelectorPlatform {
  _SavedPagePicker(this.bytes);
  List<int> bytes;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile.fromData(Uint8List.fromList(bytes), name: 'qidian.html');
}
