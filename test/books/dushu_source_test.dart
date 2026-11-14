import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/books/domain/book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Dushu search uses the current rd query parameter', () async {
    final rows =
        jsonDecode(
              await rootBundle.loadString(
                'assets/catalogs/books/verified.json',
              ),
            )
            as List;
    final source = BookSource.fromJson(
      rows.cast<Map>().firstWhere((row) => row['name'] == '读书网 · 国学古籍'),
    );
    final target = source.resolve(
      source.endpoint,
      source.search.replaceAll('{key}', Uri.encodeQueryComponent('汉书')),
    );
    expect(target.queryParameters['rd'], '汉书');
    expect(target.queryParameters, isNot(contains('qd')));
  });
}
