import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/radio/data/radio_repository.dart';
import 'package:zero_player/features/radio/data/radio_snapshot.dart';
import 'package:zero_player/features/radio/domain/radio_category.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bundled radio snapshot separates TV audio and prioritizes radio',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      final repo = RadioRepository(db, DocumentClient(http));
      try {
        final text = await rootBundle.loadString(
          'assets/catalogs/radio/cn.snapshot.json',
        );
        final snapshot = RadioSnapshot.fromJson(jsonDecode(text) as Map);
        final stations = await repo.withFavorites(
          snapshot.stations(
            RadioSubscription(name: '内置广播', url: Uri.parse(builtinRadioUrl)),
          ),
        );
        final counts = {
          for (final type in RadioCategory.values)
            type.label: stations.where((s) => radioCategory(s) == type).length,
        };
        expect(counts['广播电台'], greaterThan(0));
        expect(counts['电视伴听'], greaterThan(0));
        expect(radioCategory(stations.first), RadioCategory.radio);
        // ignore: avoid_print
        print({'total': stations.length, ...counts});
      } finally {
        await repo.close();
        http.close();
        await db.close();
      }
    },
  );
}
