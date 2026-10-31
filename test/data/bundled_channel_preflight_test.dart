import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/persistence/app_database.dart';
import 'package:zero_player/features/live/application/builtin_live_sources.dart';
import 'package:zero_player/features/live/application/channel_preflight.dart';
import 'package:zero_player/features/live/application/live_probe.dart';
import 'package:zero_player/features/live/data/live_audit_defaults.dart';
import 'package:zero_player/features/live/data/live_health_repository.dart';
import 'package:zero_player/features/live/data/live_repository.dart';
import 'package:zero_player/features/live/domain/live_health.dart';
import 'package:zero_player/features/radio/data/radio_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'frozen table has complete passed-only evidence without private media URLs',
    () async {
      final text = await rootBundle.loadString(
        'assets/live_channel_audit.json',
      );
      final data = jsonDecode(text) as Map;
      expect(data['passedOnly'], isTrue);
      expect((data['results'] as List).length, greaterThan(2500));
      for (final row in (data['results'] as List).cast<Map>()) {
        expect(row['requestSignature'], matches(r'^[a-f0-9]{64}$'));
        expect(
          (row['verifiedIndices'] as List).isNotEmpty,
          row['availability'] == 'responding',
        );
        expect(
          row.containsKey('signature'),
          isFalse,
          reason: 'raw stream tokens stay local',
        );
      }
    },
  );
  test(
    'cold install shows only preflight-passed live and radio channels without network',
    () async {
      final db = AppDatabase.memory();
      final http = MediaHttpClient();
      final audit = LiveAuditDefaults.bundled();
      final health = LiveHealthRepository(db);
      final probe = LiveProbe(http, health);
      final preflight = ChannelPreflight(audit, health, probe);
      final live = LiveRepository(db, DocumentClient(http), defaults: audit);
      final radio = RadioRepository(
        db,
        DocumentClient(http),
        preflight: preflight,
      );
      addTearDown(() async {
        await radio.close();
        await probe.close();
        http.close();
        await db.close();
      });
      await BuiltinLiveSources(live).initialize();
      final tv = (await live.channels())
          .where((c) => c.health.enabled)
          .toList();
      final stations = (await radio.load()).stations
          .where((c) => c.health.enabled)
          .toList();
      expect(tv, isNotEmpty);
      expect(stations, isNotEmpty);
      for (final channel in [...tv, ...stations]) {
        expect(channel.health.availability, LiveAvailability.responding);
        expect(channel.playbackUrls, isNotEmpty);
        expect(
          channel.playbackUrls.every(
            (u) => channel.health.verifiedUrls.contains('$u'),
          ),
          isTrue,
        );
      }
    },
  );
}
