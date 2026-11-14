import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/books/data/book_client.dart';
import 'package:zero_player/features/books/data/book_mixed_content.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/books/presentation/book_image_chapter.dart';

void main() {
  _addressParsing();
  _renderAndAdvance();
  _scrollProgress();
  _mixedLayout();
}

void _mixedLayout() {
  testWidgets('mixed chapter shows text around the image', (tester) async {
    final pending = Completer<List<int>>();
    final address = Uri.parse('https://books.test/1.png');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookImageChapter(
            images: [address],
            segments: [
              const BookTextSegment('开头文字'),
              BookImageSegment(address),
              const BookTextSegment('结尾文字'),
            ],
            loadImage: (_, _) => pending.future,
            onNext: null,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('开头文字'), findsOneWidget);
    expect(find.text('结尾文字', skipOffstage: false), findsOneWidget);
    pending.complete(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image, skipOffstage: false), findsOneWidget);
  });
}

void _addressParsing() {
  test('image chapters keep order and reject undeclared media hosts', () {
    final source = BookSource.fromJson({
      'name': '图片示例',
      'kind': 'text',
      'format': 'html',
      'url': 'https://books.test/',
      'search': '/search/{key}',
      'mediaHosts': ['images.test'],
      'rules': {
        'list': '.book',
        'title': 'a@text',
        'book': 'a@href',
        'chapters': '.chapter',
        'chapterTitle': '@text',
        'chapterUrl': '@href',
        'content': '#content@text',
      },
    });
    final images = extractBookChapterImages(
      source,
      Uri.parse('https://books.test/chapter/1'),
      '''<div id="content"><img data-src="https://images.test/1.jpg">
      <img src="/2.png"><img src="https://untrusted.test/3.jpg">
      <img src="/2.png"></div>''',
      '#content@text',
    );
    expect(images.map((uri) => uri.toString()), [
      'https://images.test/1.jpg',
      'https://books.test/2.png',
    ]);
    expect(
      parseBookImageAddresses(
        source,
        Uri.parse('https://books.test/chapter/1'),
        '["https://images.test/1.jpg", "/2.png"]',
      ),
      images,
    );
    expect(
      parseBookImageAddresses(
        source,
        Uri.parse('https://books.test/chapter/1'),
        '["https://untrusted.test/3.jpg"]',
      ),
      isEmpty,
    );
  });
}

void _renderAndAdvance() {
  testWidgets('image chapter renders and advances', (tester) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
    );
    var loaded = 0;
    var advanced = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookImageChapter(
            images: [Uri.parse('https://images.test/1.png')],
            loadImage: (_, token) async {
              token.check();
              loaded++;
              return bytes;
            },
            onNext: () => advanced = true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(loaded, 1);
    final image = find.byType(Image, skipOffstage: false);
    // A widget in the lazy list is not evidence that its pixels are visible.
    // Check the render bounds before scrolling to the next-chapter button.
    expect(image, findsOneWidget);
    expect(
      tester.getTopLeft(image).dy,
      lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio),
    );
    final raw = find.descendant(
      of: image,
      matching: find.byType(RawImage, skipOffstage: false),
      skipOffstage: false,
    );
    final decoded = tester.renderObject<RenderImage>(raw).image;
    expect(decoded, isNotNull);
    expect(decoded!.width, 2);
    expect(decoded.height, 2);
    expect(find.textContaining('格式无法解码', skipOffstage: false), findsNothing);
    await tester.dragUntilVisible(
      find.text('下一章'),
      find.byType(ListView),
      const Offset(0, -400),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('下一章'));
    expect(advanced, isTrue);
    expect(tester.takeException(), isNull);
  });
}

void _scrollProgress() {
  testWidgets('image chapter saves and restores scroll progress', (
    tester,
  ) async {
    final pending = Completer<List<int>>();
    final images = List.generate(
      3,
      (i) => Uri.parse('https://images.test/$i.png'),
    );
    double fraction = 0;
    Widget chapter(Key key, double initial) => MaterialApp(
      home: Scaffold(
        body: BookImageChapter(
          key: key,
          images: images,
          loadImage: (_, token) => pending.future,
          initialFraction: initial,
          onProgress: (value) => fraction = value,
          onNext: null,
        ),
      ),
    );
    await tester.pumpWidget(chapter(const ValueKey('first'), 0));
    await tester.pump();
    tester.state<BookImageChapterState>(find.byType(BookImageChapter)).turn(1);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 250));
    expect(fraction, greaterThan(0));
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fraction, greaterThan(0));
    final saved = fraction;
    await tester.pumpWidget(chapter(const ValueKey('restored'), saved));
    await tester.pump(const Duration(milliseconds: 300));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, greaterThan(0));
    pending.complete(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    final position = scroll.position;
    expect(position.pixels / position.maxScrollExtent, closeTo(saved, 0.15));
    expect(tester.takeException(), isNull);
  });
}
