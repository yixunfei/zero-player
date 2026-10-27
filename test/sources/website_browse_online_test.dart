import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/features/catalog/data/provider_factory.dart';
import 'package:zero_player/features/sources/domain/video_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'website categories and pagination return distinct pages',
    () async {
      final http = MediaHttpClient();
      final report = <Map<String, Object>>[];
      try {
        for (final site in [
          ('kanju', 'https://kanju3.com/', 'movie'),
          ('macCmsHtml', 'https://wu5mv.com/', '1'),
        ]) {
          final provider = createVodProvider(
            VideoSource(
              id: site.$1,
              name: site.$1,
              kind: site.$1,
              endpoint: Uri.parse(site.$2),
            ),
            DocumentClient(http),
          );
          final first = await provider.browse(category: site.$3);
          final second = await provider.browse(category: site.$3, page: 2);
          final searchFirst = await provider.search('三体');
          final searchSecond = await provider.search('三体', page: 2);
          expect(first.page.items, isNotEmpty);
          expect(second.page.items, isNotEmpty);
          expect(second.page.items.first.id, isNot(first.page.items.first.id));
          expect(searchSecond.items, isNotEmpty);
          expect(
            searchSecond.items.first.id,
            isNot(searchFirst.items.first.id),
          );
          report.add({
            'site': site.$1,
            'browsePage1': first.page.items.length,
            'browsePage2': second.page.items.length,
            'searchPage2': searchSecond.items.length,
          });
        }
      } finally {
        http.close();
        await File(
          'docs/implementation/CHANNEL-BROWSE-2026-10-27.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      }
    },
    skip: !const bool.fromEnvironment('CHANNEL_ONLINE'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
