import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../../core/persistence/app_database.dart';
import '../../../app/app_fonts.dart';
import '../domain/settings_validation.dart';

final class UserSettings {
  const UserSettings({
    this.theme = 'cinema',
    this.font = 'xiaolai',
    this.startFullscreen = true,
    this.navigationGuideSeen = false,
    this.manualLoadCount = 48,
    this.mode = 'auto',
    this.autoplay = true,
    this.cache = true,
    this.cacheMiB = 512,
    this.episodeCacheMiB = 256,
    this.prefetchSegments = 3,
    this.cacheWhilePaused = false,
    this.downloadMiB = 4096,
    this.skip = true,
    this.adFilter = false,
    this.filterAdult = true,
    this.recommendation = 'douban',
    this.homeChannel = '',
    this.homeLayout = 'single',
    this.allowMetered = false,
    this.searchConcurrency = 6,
    this.probeConcurrency = 3,
    this.backgroundProbe = true,
    this.autoDownloadFallback = true,
    this.multiSourceDownload = false,
    this.downloadConcurrency = 2,
    this.gestures = true,
  });
  final String theme;
  final String font;
  final bool startFullscreen;
  final bool navigationGuideSeen;
  final int manualLoadCount;
  final String mode;
  final bool autoplay;
  final bool cache;
  final int cacheMiB;
  final int episodeCacheMiB;
  final int prefetchSegments;
  final bool cacheWhilePaused;
  final int downloadMiB;
  final bool skip;
  final bool adFilter;
  final bool filterAdult;
  final String recommendation;
  final String homeChannel;
  final String homeLayout;
  final bool allowMetered;
  final int searchConcurrency;
  final int probeConcurrency;
  final bool backgroundProbe;
  final bool autoDownloadFallback;
  final bool multiSourceDownload;
  final int downloadConcurrency;
  final bool gestures;

  Map<String, Object> toMap() => {
    'theme': theme,
    'font': font,
    'startFullscreen': startFullscreen,
    'navigationGuideSeen': navigationGuideSeen,
    'manualLoadCount': manualLoadCount,
    'mode': mode,
    'autoplay': autoplay,
    'cache': cache,
    'cacheMiB': cacheMiB,
    'episodeCacheMiB': episodeCacheMiB,
    'prefetchSegments': prefetchSegments,
    'cacheWhilePaused': cacheWhilePaused,
    'downloadMiB': downloadMiB,
    'skip': skip,
    'adFilter': adFilter,
    'filterAdult': filterAdult,
    'recommendation': recommendation,
    'homeChannel': homeChannel,
    'homeLayout': homeLayout,
    'allowMetered': allowMetered,
    'searchConcurrency': searchConcurrency,
    'probeConcurrency': probeConcurrency,
    'backgroundProbe': backgroundProbe,
    'autoDownloadFallback': autoDownloadFallback,
    'multiSourceDownload': multiSourceDownload,
    'downloadConcurrency': downloadConcurrency,
    'gestures': gestures,
  };

  factory UserSettings.fromMap(Map<String, Object?> map) => UserSettings(
    font: appFontLabels.containsKey(map['font'])
        ? map['font'] as String
        : 'xiaolai',
    startFullscreen: map['startFullscreen'] != false,
    navigationGuideSeen: map['navigationGuideSeen'] == true,
    manualLoadCount: ((map['manualLoadCount'] as num?)?.toInt() ?? 48).clamp(
      12,
      240,
    ),
    theme: {'cinema', 'dark', 'light', 'system'}.contains(map['theme'])
        ? map['theme'] as String
        : 'cinema',
    mode: {'auto', 'television'}.contains(map['mode'])
        ? map['mode'] as String
        : 'auto',
    autoplay: map['autoplay'] != false,
    cache: map['cache'] != false,
    cacheMiB: ((map['cacheMiB'] as num?)?.toInt() ?? 512).clamp(64, 16384),
    episodeCacheMiB: ((map['episodeCacheMiB'] as num?)?.toInt() ?? 256).clamp(
      64,
      2048,
    ),
    prefetchSegments: ((map['prefetchSegments'] as num?)?.toInt() ?? 3).clamp(
      0,
      10,
    ),
    cacheWhilePaused: map['cacheWhilePaused'] == true,
    downloadMiB: ((map['downloadMiB'] as num?)?.toInt() ?? 4096).clamp(
      128,
      1048576,
    ),
    skip: map['skip'] != false,
    adFilter: map['adFilter'] == true,
    filterAdult: map['filterAdult'] != false,
    recommendation: {'douban', 'off'}.contains(map['recommendation'])
        ? map['recommendation'] as String
        : 'douban',
    allowMetered: map['allowMetered'] == true,
    homeChannel:
        map['homeChannel'] is String &&
            (map['homeChannel'] as String).length <= 128
        ? map['homeChannel'] as String
        : '',
    homeLayout: map['homeLayout'] == 'aggregate' ? 'aggregate' : 'single',
    searchConcurrency: ((map['searchConcurrency'] as num?)?.toInt() ?? 6).clamp(
      1,
      16,
    ),
    probeConcurrency: ((map['probeConcurrency'] as num?)?.toInt() ?? 3).clamp(
      1,
      6,
    ),
    backgroundProbe: map['backgroundProbe'] != false,
    autoDownloadFallback: map['autoDownloadFallback'] != false,
    multiSourceDownload: map['multiSourceDownload'] == true,
    downloadConcurrency: ((map['downloadConcurrency'] as num?)?.toInt() ?? 2)
        .clamp(1, 4),
    gestures: map['gestures'] != false,
  );
}

final class SettingsController extends ChangeNotifier {
  SettingsController(this.db, {this.authorize});
  final AppDatabase db;
  final void Function()? authorize;
  UserSettings value = const UserSettings();
  Future<void> _pending = Future.value();
  Future<void>? _closing;
  bool _disposed = false;
  Future<void> load() async {
    if (_disposed || _closing != null) throw StateError('Settings are closed');
    final rows = await db.rows('SELECT key,value FROM settings');
    final values = <String, Object?>{};
    for (final row in rows) {
      final key = row['key'] as String;
      try {
        var decoded = jsonDecode(row['value'] as String);
        if (key == 'recommendation' && {'bangumi', 'hot'}.contains(decoded)) {
          decoded = 'douban';
          await db.write('UPDATE settings SET value=? WHERE key=?', [
            jsonEncode(decoded),
            key,
          ]);
        }
        validateSetting(key, decoded);
        values[key] = decoded;
      } on FormatException {
        debugPrint('Ignoring invalid setting: $key');
      }
    }
    value = UserSettings.fromMap(values);
    if (!_disposed) notifyListeners();
  }

  Future<void> update(Map<String, Object> changes) {
    if (_disposed || _closing != null) {
      return Future.error(StateError('Settings are closed'));
    }
    final patch = Map<String, Object>.of(changes);
    final operation = _pending.then((_) => _update(patch));
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _update(Map<String, Object> changes) async {
    if (changes['filterAdult'] == false) authorize?.call();
    for (final entry in changes.entries) {
      validateSetting(entry.key, entry.value);
    }
    final next = UserSettings.fromMap({...value.toMap(), ...changes});
    await db.atomic(() async {
      if (changes['filterAdult'] == false) authorize?.call();
      for (final entry in changes.entries) {
        await db.customStatement(
          'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
          [entry.key, jsonEncode(entry.value)],
        );
      }
    }, tables: const {'settings'});
    value = next;
    if (!_disposed) notifyListeners();
  }

  Future<void> close() => _closing ??= _pending.then((_) => dispose());

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
