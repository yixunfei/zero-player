import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'schema.dart';

/// Current development schema; no legacy-format migration scaffolding.
final class AppDatabase extends GeneratedDatabase {
  AppDatabase(File file) : super(NativeDatabase.createInBackground(file));
  AppDatabase.memory() : super(NativeDatabase.memory());
  final _changes = StreamController<Set<String>?>.broadcast();
  bool _closed = false;
  Future<void>? _closing;
  Stream<void> get changes => _changes.stream.map((_) {});
  Stream<void> changesFor(Set<String> tables) => _changes.stream
      .where((changed) => changed == null || changed.any(tables.contains))
      .map((_) {});
  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => transaction(() async {
      for (final sql in schemaStatements) {
        await customStatement(sql);
      }
    }),
    onUpgrade: (_, from, to) => transaction(() async {
      // Preserve the user's current sources, history and offline tasks.
      if (from == 1 && to == 2) {
        await customStatement(
          'CREATE TABLE IF NOT EXISTS app_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await _addColumn('sources', 'site_title', 'TEXT');
        await _addColumn('sources', 'homepage', 'TEXT');
        await _addColumn('source_health', 'latency_ms', 'INTEGER');
        await _addColumn('downloads', 'work_json', 'TEXT');
      } else {
        throw StateError('Unsupported database migration: $from -> $to');
      }
    }),
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );

  Future<void> _addColumn(String table, String name, String type) async {
    final columns = await rows('PRAGMA table_info($table)');
    if (!columns.any((column) => column['name'] == name)) {
      await customStatement('ALTER TABLE $table ADD COLUMN $name $type');
    }
  }

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    _checkOpen();
    final result = await customSelect(
      sql,
      variables: args.map(_variable).toList(),
    ).get();
    return result.map((row) => Map<String, Object?>.from(row.data)).toList();
  }

  Variable _variable(Object? value) => switch (value) {
    int v => Variable<int>(v),
    double v => Variable<double>(v),
    bool v => Variable<bool>(v),
    String v => Variable<String>(v),
    null => const Variable<String>(null),
    _ => throw ArgumentError('Unsupported SQL value'),
  };

  Future<void> write(String sql, [List<Object?> args = const []]) async {
    _checkOpen();
    await customStatement(sql, args);
    final match = RegExp(
      r'^\s*(?:INSERT(?:\s+OR\s+\w+)?\s+INTO|UPDATE(?:\s+OR\s+\w+)?|DELETE\s+FROM)\s+([a-z_][a-z_0-9]*)',
      caseSensitive: false,
    ).firstMatch(sql);
    changed(tables: match == null ? null : {match[1]!.toLowerCase()});
  }

  void changed({Set<String>? tables}) {
    if (!_changes.isClosed) {
      _changes.add(tables == null ? null : Set.unmodifiable(tables));
    }
  }

  Future<T> atomic<T>(Future<T> Function() work, {Set<String>? tables}) async {
    _checkOpen();
    final result = await transaction(work);
    changed(tables: tables);
    return result;
  }

  @override
  Future<void> close() => _closing ??= _close();

  void _checkOpen() {
    if (_closed) throw StateError('Database is closed');
  }

  Future<void> _close() async {
    _closed = true;
    await _changes.close();
    await super.close();
  }
}
