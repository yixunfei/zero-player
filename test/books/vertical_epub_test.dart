import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/books/presentation/vertical_book_text.dart';
import 'package:zero_player/features/books/presentation/vertical_epub_flow.dart';

void main() {
  const style = TextStyle(fontSize: 21);
  const source =
      '<p>前<ruby>漢<rt>hàn</rt>字<rt>zì</rt></ruby>後</p>'
      '<figure><img alt="图"/><figcaption>图注</figcaption></figure>'
      '<pre><code>docker run</code></pre><p>末尾</p>';
  test('vertical flow preserves ruby pairs and mixed block reading order', () {
    final items = verticalEpubItems(source, style);
    expect(items.where((i) => i.ruby.isNotEmpty).map((i) => i.ruby), [
      'hàn',
      'zì',
    ]);
    expect(
      items
          .where((i) => i.html == null)
          .map((i) => i.text)
          .join()
          .replaceAll(RegExp(r'\n+'), '\n'),
      '前漢字後\n末尾\n',
    );
    final pages = paginateVertical(items, const Size(280, 500));
    expect(pages, hasLength(4));
    expect(pages[1].html, contains('图注'));
    expect(pages[2].html, contains('docker run'));
    expect(pages.last.columns.single.items.map((i) => i.text).join(), '末尾');
  });
  test('vertical pagination does not lose long text across narrow pages', () {
    final text = List.filled(200, '天地玄黄').join();
    final pages = paginateVertical(
      verticalEpubItems('<p>$text</p>', style),
      const Size(250, 300),
    );
    expect(pages.length, greaterThan(1));
    expect(
      pages
          .expand((p) => p.columns)
          .expand((c) => c.items)
          .map((i) => i.text)
          .join()
          .replaceAll(RegExp(r'\n+'), '\n'),
      text,
    );
    for (final page in pages) {
      expect(
        page.columns.fold<double>(0, (w, c) => w + c.width),
        lessThanOrEqualTo(250),
      );
      for (final column in page.columns) {
        expect(
          column.items.fold<double>(0, (h, i) => h + i.extent),
          lessThanOrEqualTo(300),
        );
      }
    }
  });
  testWidgets('vertical ruby and code remain reachable at phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<VerticalBookTextState>();
    var page = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerticalBookText(
            key: key,
            text: '',
            html: source,
            style: style,
            onBoundary: (_) {},
            onPageChanged: (i) => page = i,
          ),
        ),
      ),
    );
    expect(find.text('漢'), findsOneWidget);
    expect(find.text('h\nà\nn'), findsOneWidget);
    key.currentState!.turn(1);
    await tester.pumpAndSettle();
    expect(page, 1);
    expect(find.text('图注', findRichText: true), findsWidgets);
    key.currentState!.turn(1);
    await tester.pumpAndSettle();
    expect(find.textContaining('docker run', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
