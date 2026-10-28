import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/discovery/data/release_calendar.dart';

void main() {
  test('validate downloaded public release calendar', () async {
    final items = parseReleaseCalendar(
      await File('build/douban-coming.html').readAsString(),
    );
    expect(items, isNotEmpty);
    // ignore: avoid_print
    print({
      'count': items.length,
      'firstDate': items.first.date,
      'lastDate': items.last.date,
    });
  });
}
