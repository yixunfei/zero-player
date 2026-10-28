import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../core/network/cancellation_token.dart';
import '../../../core/persistence/app_database.dart';
import '../domain/radio_subscription.dart';
import 'radio_snapshot.dart';

/// Database snapshots and atomic files contain only fully parsed successful lists.
final class RadioSnapshotStore {
  RadioSnapshotStore(this.db, {this.directory});
  final AppDatabase db;
  final Directory? directory;
  Future<void> _writes = Future<void>.value();

  File? file(RadioSubscription subscription) => directory == null
      ? null
      : File(p.join(directory!.path, '${subscription.id}.json'));

  Future<RadioSnapshot?> read(RadioSubscription subscription) async {
    final rows = await db.rows('SELECT value FROM app_meta WHERE key=?', [
      'radio_snapshot:${subscription.url}',
    ]);
    if (rows.isNotEmpty) {
      final snapshot = _decode(rows.single['value'] as String, subscription);
      if (snapshot != null) return snapshot;
    }
    final saved = file(subscription);
    if (saved != null && await saved.exists()) {
      try {
        final snapshot = _decode(await saved.readAsString(), subscription);
        if (snapshot != null) return snapshot;
      } on FileSystemException {
        /* Try the bundled snapshot. */
      }
    }
    if (subscription.url.toString() != builtinRadioUrl) return null;
    try {
      return _decode(
        await rootBundle.loadString('assets/catalogs/radio/cn.snapshot.json'),
        subscription,
      );
    } on Exception {
      return null;
    }
  }

  RadioSnapshot? _decode(String input, RadioSubscription subscription) {
    try {
      final data = jsonDecode(input);
      if (data is! Map) return null;
      final snapshot = RadioSnapshot.fromJson(data);
      snapshot.stations(subscription);
      return snapshot;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> save(
    RadioSubscription subscription,
    RadioSnapshot snapshot, {
    required CancellationToken cancellation,
    required bool Function() isCurrent,
  }) {
    final next = _writes.then((_) async {
      cancellation.check();
      if (!isCurrent()) return;
      snapshot.stations(subscription);
      final text = jsonEncode(snapshot.toJson());
      final target = file(subscription);
      final temporary = target == null ? null : File('${target.path}.tmp');
      try {
        if (temporary != null) {
          await temporary.parent.create(recursive: true);
          await temporary.writeAsString(text, flush: true);
        }
        await db.atomic(() async {
          cancellation.check();
          if (!isCurrent()) return;
          if (temporary != null) await temporary.rename(target!.path);
          await db.customStatement(
            'INSERT OR REPLACE INTO app_meta VALUES(?,?)',
            ['radio_snapshot:${subscription.url}', text],
          );
        }, tables: const {'app_meta'});
      } finally {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      }
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> close() => _writes;
}
