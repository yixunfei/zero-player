import 'dart:convert';
import 'dart:io';

import '../../../core/network/header_policy.dart';
import '../../../core/network/lan_access_policy.dart';
import '../../../core/network/network_target_policy.dart';
import '../../../core/persistence/app_database.dart';

/// Local permissions are never populated by source imports or portable backups.
final class LanAccessStore {
  LanAccessStore(this.db, {required this.authorize, required this.onChanged});
  final AppDatabase db;
  final void Function() authorize;
  final void Function() onChanged;
  static const storageKey = 'network_lan_origins';
  Set<String> _origins = {};
  Future<void>? _loading;
  Future<void>? _pending;
  bool _closed = false;
  List<String> get origins => _origins.toList()..sort();
  bool allows(Uri uri) => _origins.contains(HeaderPolicy.origin(uri));

  static String validate(String value) {
    final uri = Uri.parse(value.trim());
    NetworkTargetPolicy.validateUri(uri);
    final address = InternetAddress.tryParse(uri.host);
    if (address == null ||
        !isLanAddress(address) ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        '请输入局域网 IP 和端口，例如 http://192.168.1.10:8080；不包含路径或参数',
      );
    }
    return HeaderPolicy.origin(uri);
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final rows = await db.rows('SELECT value FROM app_meta WHERE key=?', [
      storageKey,
    ]);
    if (rows.isEmpty) return;
    try {
      final decoded = jsonDecode(rows.single['value'] as String);
      if (decoded is! List ||
          decoded.length > 32 ||
          decoded.any((entry) => entry is! String)) {
        throw const FormatException('Invalid LAN permissions');
      }
      _origins = decoded.cast<String>().map(validate).toSet();
    } on FormatException {
      _origins = {};
    }
  }

  Future<void> grant(String origin) => _change(validate(origin), true);
  Future<void> revoke(String origin) => _change(validate(origin), false);

  Future<void> _change(String origin, bool grant) {
    if (_closed) return Future.error(StateError('局域网授权管理已关闭'));
    final operation = (_pending ?? Future<void>.value()).then((_) async {
      await load();
      authorize();
      final next = {..._origins};
      if (grant) {
        next.add(origin);
      } else {
        next.remove(origin);
      }
      if (next.length > 32) throw const FormatException('局域网授权最多 32 项');
      await db.write('INSERT OR REPLACE INTO app_meta(key,value) VALUES(?,?)', [
        storageKey,
        jsonEncode(next.toList()..sort()),
      ]);
      _origins = next;
      onChanged();
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> close() async {
    _closed = true;
    await _pending;
  }
}
