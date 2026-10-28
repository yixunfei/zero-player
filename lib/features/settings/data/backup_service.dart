import 'dart:convert';
import '../../../core/persistence/app_database.dart';
import 'backup_validation.dart';

final class BackupPreview {
  const BackupPreview(this.tables);
  final Map<String, List<Map<String, Object?>>> tables;
  int get sourceCount => tables['sources']!.length;
  int get historyCount => tables['watch_history']!.length;
}

final class BackupService {
  const BackupService(this.db, {this.authorize, this.authorizeExport});
  final AppDatabase db;
  final void Function()? authorize;
  final void Function()? authorizeExport;
  static const maxBytes = 20 * 1024 * 1024;
  static const maxRowsPerTable = 20000;
  static const tables = [
    'settings',
    'sources',
    'source_overrides',
    'subscriptions',
    'source_memberships',
    'search_history',
    'watch_history',
    'skip_marks',
    'skip_preferences',
    'live_lists',
    'live_channels',
    'channel_preferences',
    'app_meta',
  ];
  static const _liveMetadata =
      " WHERE key GLOB 'live_headers:*' OR key GLOB 'live_state:*' OR key GLOB 'live_list_enabled:*' OR key GLOB 'live_metadata:*'"
      " OR key='radio_subscriptions' OR key GLOB 'radio_favorite:*' OR key GLOB 'radio_snapshot:*'"
      " OR key GLOB 'source_favorite:*'";

  Future<String> export() async => db.transaction(() async {
    authorizeExport?.call();
    final data = <String, Object>{};
    for (final name in tables) {
      data[name] = await db.rows(
        'SELECT * FROM $name${name == 'app_meta' ? _liveMetadata : ''} '
        'LIMIT ${maxRowsPerTable + 1}',
      );
      if ((data[name] as List).length > maxRowsPerTable) {
        throw FormatException('$name 超过备份上限 $maxRowsPerTable 行，未生成备份');
      }
    }
    final text = jsonEncode({
      'format': 'ZeroPlayer-Backup',
      'version': 2,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'mediaIncluded': false,
      'tables': data,
    });
    // Never offer a successfully exported file that our importer rejects.
    await preview(text);
    authorizeExport?.call();
    return text;
  });

  Future<BackupPreview> preview(String text) async {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('备份超过 20 MiB');
    }
    final raw = jsonDecode(text);
    if (raw is! Map ||
        raw['format'] != 'ZeroPlayer-Backup' ||
        raw['version'] != 2 ||
        raw['tables'] is! Map) {
      throw const FormatException('不是受支持的 Zero Player 备份');
    }
    final result = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      final rows = raw['tables'][table];
      if (rows is! List || rows.length > maxRowsPerTable) {
        throw FormatException('$table 数据不完整或数量超限');
      }
      final schema = await db.rows('PRAGMA table_info($table)');
      result[table] = [];
      for (final row in rows) {
        _validateRow(row, schema);
        validateBackupRecord(table, row as Map);
        result[table]!.add(
          Map<String, Object?>.unmodifiable(Map<String, Object?>.from(row)),
        );
      }
    }
    return BackupPreview(
      Map.unmodifiable({
        for (final e in result.entries)
          e.key: List<Map<String, Object?>>.unmodifiable(e.value),
      }),
    );
  }

  void _validateRow(Object? input, List<Map<String, Object?>> schema) {
    if (input is! Map || input.length != schema.length) {
      throw const FormatException('备份字段不完整');
    }
    for (final field in schema) {
      final key = field['name'] as String;
      if (!input.containsKey(key)) throw const FormatException('备份缺少字段');
      final value = input[key];
      if (value == null) {
        if (field['notnull'] == 1 || field['pk'] == 1) {
          throw const FormatException('必填字段为空');
        }
      } else if (field['type'] == 'INTEGER'
          ? value is! int
          : value is! String) {
        throw const FormatException('字段类型不正确');
      }
    }
  }

  Future<void> restore(BackupPreview preview) => db.atomic(() async {
    authorize?.call();
    for (final table in tables.reversed) {
      await db.customStatement(
        'DELETE FROM $table${table == 'app_meta' ? _liveMetadata : ''}',
      );
    }
    for (final table in tables) {
      for (final row in preview.tables[table]!) {
        final fields = row.keys.toList();
        await db.customStatement(
          'INSERT INTO $table (${fields.join(',')}) VALUES '
          '(${List.filled(fields.length, '?').join(',')})',
          fields.map((key) => row[key]).toList(),
        );
      }
    }
    // FK, CHECK and uniqueness failures roll the entire operation back.
    final violations = await db.rows('PRAGMA foreign_key_check');
    if (violations.isNotEmpty) throw const FormatException('备份包含无效的数据关联');
  });
}
