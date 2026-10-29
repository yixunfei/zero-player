import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/persistence/app_database.dart';
import '../data/password_hasher.dart';
import '../domain/supervision_rules.dart';

/// Local application protection. Credentials never enter normal data backups.
final class SupervisionController extends ChangeNotifier {
  SupervisionController(
    this.db, {
    this._hasher = const PasswordHasher(),
    DateTime Function()? clock,
    this.protectContentFilter,
  }) : _clock = clock ?? DateTime.now;
  static const storageKey = 'supervision:v1';
  final AppDatabase db;
  final CredentialHasher _hasher;
  final DateTime Function() _clock;
  final bool Function()? protectContentFilter;
  final Object _zoneKey = Object();
  Future<void>? _loading;
  Future<void>? _closing;
  bool _closed = false;
  Future<void> _stateQueue = Future.value();
  Map<String, String>? _password, _recovery;
  SupervisionRules _rules = SupervisionRules();
  bool _enabled = false, _corrupted = false, _loaded = false;
  SupervisionRules get rules => _rules;
  bool get enabled => _enabled;
  bool get corrupted => _corrupted;
  int _revision = 0, _failures = 0;
  DateTime? _retryAfter;
  bool get configured => _password != null || corrupted;

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final rows = await db.rows('SELECT value FROM app_meta WHERE key=?', [
      storageKey,
    ]);
    if (rows.isNotEmpty) {
      try {
        final raw = jsonDecode(rows.single['value'] as String) as Map;
        if (raw['version'] != 1 || raw['enabled'] is! bool) {
          throw const FormatException('监管配置版本无效');
        }
        _password = Map<String, String>.from(raw['password'] as Map);
        _recovery = Map<String, String>.from(raw['recovery'] as Map);
        _hasher.validate(_password!);
        _hasher.validate(_recovery!);
        _rules = SupervisionRules.fromJson(raw['rules'] as Map);
        _enabled = raw['enabled'] as bool;
        _failures = (raw['failures'] as int).clamp(0, 100);
        final retry = raw['retryAfter'] as int?;
        _retryAfter = retry == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(retry);
      } catch (_) {
        _corrupted = true;
        _enabled = true;
      }
    }
    _loaded = true;
    notifyListeners();
  }

  bool needsPassword(SensitiveOperation operation) =>
      corrupted ||
      (configured &&
          (operation == SensitiveOperation.supervision ||
              (enabled &&
                  (operation != SensitiveOperation.contentFilter ||
                      (protectContentFilter?.call() ?? false)))));

  /// Changing an authorization policy revokes any open management capability.
  void invalidatePermissions() => _revision++;

  bool allows(SensitiveOperation operation) {
    try {
      require(operation);
      return true;
    } on FormatException {
      return false;
    }
  }

  void require(SensitiveOperation operation, {bool allowRecovery = false}) {
    if (_closed) throw const FormatException('应用正在退出');
    if (!_loaded) throw const FormatException('监管配置尚未加载，请稍后重试');
    if (corrupted) throw const FormatException('监管配置损坏，已保持锁定');
    if (!needsPassword(operation)) return;
    final grant = Zone.current[_zoneKey];
    if (grant is! _OperationGrant ||
        !grant.active ||
        grant.operation != operation ||
        grant.revision != _revision ||
        (grant.recovery && !allowRecovery)) {
      throw const FormatException('此操作需要验证监管密码');
    }
  }

  Future<T> execute<T>(
    SensitiveOperation operation,
    Future<T> Function() body, {
    String? password,
    bool useRecovery = false,
  }) async {
    await load();
    if (_closed) throw const FormatException('应用正在退出');
    if (useRecovery && operation != SensitiveOperation.supervision) {
      throw const FormatException('恢复码仅用于重设监管凭据');
    }
    var revision = _revision;
    if (needsPassword(operation)) {
      if (password == null || password.isEmpty) {
        throw const FormatException('请输入监管密码');
      }
      revision = await _serialize(
        () => _verify(password, recovery: useRecovery),
      );
    }
    if (_closed || revision != _revision) {
      throw const FormatException('监管配置已变更，请重新验证');
    }
    final grant = _OperationGrant(operation, revision, useRecovery);
    return runZoned(() async {
      try {
        return await body();
      } finally {
        grant.active = false;
      }
    }, zoneValues: {_zoneKey: grant});
  }

  Future<T> _serialize<T>(Future<T> Function() body) {
    final operation = _stateQueue.then((_) => body());
    _stateQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  /// A capability owned by one management route; no password is retained.
  SensitiveSession createSession(SensitiveOperation operation) {
    require(operation);
    return SensitiveSession._(
      this,
      _OperationGrant(operation, _revision, false),
    );
  }

  Future<int> _verify(String input, {required bool recovery}) async {
    if (corrupted) throw const FormatException('监管配置损坏，已保持锁定');
    final now = _clock();
    if (_retryAfter != null && now.isBefore(_retryAfter!)) {
      throw const FormatException('验证失败次数过多，请稍后再试');
    }
    if (input.length > 256 ||
        !await _hasher.verify(input, recovery ? _recovery! : _password!)) {
      _failures++;
      if (_failures >= 5) {
        _retryAfter = now.add(
          Duration(
            seconds: (30 * (1 << (_failures - 5).clamp(0, 4))).clamp(30, 300),
          ),
        );
      }
      await _persist();
      throw const FormatException('密码或恢复码不正确');
    }
    _failures = 0;
    _retryAfter = null;
    await _persist();
    return _revision;
  }

  Future<PendingCredentials> prepareCredentials(String password) async {
    await load();
    require(SensitiveOperation.supervision, allowRecovery: true);
    if (password.length < 8 ||
        password.length > 128 ||
        password.trim().isEmpty) {
      throw const FormatException('密码需为 8–128 个字符');
    }
    final recoveryCode = _hasher.recoveryCode();
    final revision = _revision;
    final passwordHash = await _hasher.hash(password);
    final recoveryHash = await _hasher.hash(recoveryCode);
    require(SensitiveOperation.supervision, allowRecovery: true);
    if (revision != _revision) throw const FormatException('监管配置已变更，请重新设置');
    return PendingCredentials._(
      this,
      revision,
      recoveryCode,
      passwordHash,
      recoveryHash,
    );
  }

  Future<void> saveCredentials(PendingCredentials draft) =>
      _serialize(() async {
        require(SensitiveOperation.supervision, allowRecovery: true);
        if (!identical(draft._owner, this) ||
            draft._used ||
            draft._revision != _revision) {
          throw const FormatException('密码设置已失效，请重新开始');
        }
        final initial = !configured;
        _failures = 0;
        _retryAfter = null;
        await _commit(
          password: draft._password,
          recovery: draft._recovery,
          enabled: initial ? true : enabled,
        );
        draft._used = true;
      });

  Future<void> setEnabled(bool value) => _serialize(() async {
    require(SensitiveOperation.supervision);
    if (!configured) throw const FormatException('请先设置监管密码');
    await _commit(enabled: value);
  });

  Future<void> updateRules(SupervisionRules value) => _serialize(() async {
    require(SensitiveOperation.supervision);
    if (!configured) throw const FormatException('请先设置监管密码');
    await _commit(rules: value);
  });

  Future<void> _commit({
    bool? enabled,
    SupervisionRules? rules,
    Map<String, String>? password,
    Map<String, String>? recovery,
  }) async {
    final nextEnabled = enabled ?? this.enabled;
    final nextRules = rules ?? this.rules;
    final nextPassword = password ?? _password;
    final nextRecovery = recovery ?? _recovery;
    await db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
      storageKey,
      jsonEncode({
        'version': 1,
        'enabled': nextEnabled,
        'password': nextPassword,
        'recovery': nextRecovery,
        'rules': nextRules.toJson(),
        'failures': _failures,
        'retryAfter': _retryAfter?.millisecondsSinceEpoch,
      }),
    ]);
    _enabled = nextEnabled;
    _rules = nextRules;
    _password = nextPassword;
    _recovery = nextRecovery;
    _revision++;
    notifyListeners();
  }

  Future<void> _persist() =>
      db.write('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
        storageKey,
        jsonEncode({
          'version': 1,
          'enabled': enabled,
          'password': _password,
          'recovery': _recovery,
          'rules': rules.toJson(),
          'failures': _failures,
          'retryAfter': _retryAfter?.millisecondsSinceEpoch,
        }),
      ]);
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _revision++;
    await _stateQueue;
    dispose();
  }
}

final class SensitiveSession {
  SensitiveSession._(this._owner, this._grant);
  final SupervisionController _owner;
  final _OperationGrant _grant;

  Future<T> run<T>(Future<T> Function() action) async {
    if (!_grant.active) throw const FormatException('管理会话已关闭，请重新进入');
    if (_owner._closed || _owner._revision != _grant.revision) {
      throw const FormatException('监管配置已变更，请重新进入管理');
    }
    return runZoned(() async {
      _owner.require(_grant.operation);
      return await action();
    }, zoneValues: {_owner._zoneKey: _grant});
  }

  void close() => _grant.active = false;
}

final class PendingCredentials {
  PendingCredentials._(
    this._owner,
    this._revision,
    this.recoveryCode,
    this._password,
    this._recovery,
  );
  final SupervisionController _owner;
  final int _revision;
  final String recoveryCode;
  final Map<String, String> _password, _recovery;
  bool _used = false;
}

final class _OperationGrant {
  _OperationGrant(this.operation, this.revision, this.recovery);
  final SensitiveOperation operation;
  final int revision;
  final bool recovery;
  bool active = true;
}
