import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/network/cancellation_token.dart';
import '../data/books_repository.dart';
import '../domain/book.dart';

/// Cover requests use the book source's declared hosts and bounded client.
class BookCover extends StatefulWidget {
  const BookCover({super.key, required this.book, required this.repository});
  final Book book;
  final BooksRepository repository;
  @override
  State<BookCover> createState() => _BookCoverState();
}

class _BookCoverState extends State<BookCover> {
  CancellationToken? _token;
  Future<Uint8List>? _bytes;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _token?.cancel();
    _bytes = widget.book.cover.isEmpty
        ? null
        : widget.repository
              .coverBytes(widget.book, _token = CancellationToken())
              .then(
                (bytes) =>
                    bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
              );
  }

  @override
  void didUpdateWidget(BookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.book.id != widget.book.id ||
        oldWidget.book.cover != widget.book.cover) {
      _load();
    }
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(7),
    child: FutureBuilder<Uint8List>(
      key: ValueKey((widget.book.id, widget.book.cover)),
      future: _bytes,
      builder: (context, snapshot) => snapshot.hasData
          ? Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              cacheWidth: 360,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => _ClothCover(book: widget.book),
            )
          : _ClothCover(book: widget.book),
    ),
  );
}

final class _ClothCover extends StatelessWidget {
  const _ClothCover({required this.book});
  final Book book;

  static const _palettes = [
    (Color(0xff254a43), Color(0xffe9dfb7)),
    (Color(0xff623b38), Color(0xfff5ddc4)),
    (Color(0xff293e56), Color(0xffdce6eb)),
    (Color(0xff55463c), Color(0xffffedc7)),
    (Color(0xff47435e), Color(0xfff0e5ef)),
  ];

  @override
  Widget build(BuildContext context) {
    final index =
        int.parse(book.id.substring(0, 2), radix: 16) % _palettes.length;
    final (cloth, ink) = _palettes[index];
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final compact = width < 74 || height < 90;
          return CustomPaint(
            painter: _CoverLines(cloth, ink),
            child: SizedBox.expand(
              child: compact
                  ? Center(
                      child: Icon(
                        Icons.auto_stories_outlined,
                        color: ink,
                        size: math.min(width * .48, 28),
                      ),
                    )
                  : Padding(
                      padding: EdgeInsets.fromLTRB(
                        width * .15,
                        height * .12,
                        width * .12,
                        height * .22,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: width * .17,
                            child: Divider(color: ink, thickness: 1, height: 8),
                          ),
                          const SizedBox(height: 7),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                book.title,
                                maxLines: height < 140 ? 2 : 4,
                                overflow: TextOverflow.ellipsis,
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  fontFamily: 'NotoSerifSC',
                                  fontSize: (width * .16).clamp(13, 29),
                                  height: 1.26,
                                  fontWeight: FontWeight.w700,
                                  color: ink,
                                ),
                              ),
                            ),
                          ),
                          if (height >= 136 && book.author.isNotEmpty)
                            Text(
                              book.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(fontSize: 10, color: ink),
                            ),
                        ],
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

final class _CoverLines extends CustomPainter {
  const _CoverLines(this.cloth, this.ink);
  final Color cloth, ink;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final spine = (size.width * .065).clamp(3.0, 14.0);
    canvas.drawRect(rect, Paint()..color = cloth);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, spine, size.height),
      Paint()..color = Colors.black26,
    );
    final border = Paint()
      ..color = ink.withValues(alpha: .33)
      ..strokeWidth = .65
      ..style = PaintingStyle.stroke;
    canvas.drawRect(
      Rect.fromLTRB(spine + 4, 5, size.width - 5, size.height - 5),
      border,
    );
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        spine + 4,
        size.height * .8,
        size.width - 5,
        size.height - 5,
      ),
    );
    for (var index = 0; index < 7; index++) {
      final radius = size.width * (.28 + index * .07);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * .69, size.height * 1.06),
          width: radius * 2,
          height: radius * 1.06,
        ),
        border,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoverLines oldDelegate) =>
      oldDelegate.cloth != cloth || oldDelegate.ink != ink;
}
