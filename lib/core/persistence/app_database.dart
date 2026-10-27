import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'schema.dart';

/// Current development schema; no legacy-format migration scaffolding.
final class AppDatabase extends GeneratedDatabase {
  AppDatabase(File file) : super(NativeDatabase.createInBackground(file));
  AppDatabase.memory() : super(NativeDatabase.memory());
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final sql in schemaStatements) {
        await customStatement(sql);
      }
    },
    onUpgrade: (_, from, to) async {
      // Preserve the user's current sources, history and offline tasks.
      if (from == 1) {
        await customStatement(
          'CREATE TABLE app_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await customStatement('ALTER TABLE sources ADD COLUMN site_title TEXT');
        await customStatement('ALTER TABLE sources ADD COLUMN homepage TEXT');
        await customStatement(
          'ALTER TABLE source_health ADD COLUMN latency_ms INTEGER',
        );
        await customStatement(
          'ALTER TABLE downloads ADD COLUMN work_json TEXT',
        );
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) async {
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
    await customStatement(sql, args);
    changed();
  }

  void changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<T> atomic<T>(Future<T> Function() work) async {
    final result = await transaction(work);
    changed();
    return result;
  }

  @override
  Future<void> close() async {
    await _changes.close();
    await super.close();
  }
}
