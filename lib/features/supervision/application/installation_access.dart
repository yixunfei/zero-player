import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/persistence/app_database.dart';
import '../../../core/persistence/installation_metadata.dart';
import '../data/password_hasher.dart';

/// Installation-local consent; an embedded verifier is not a device security boundary.
final class InstallationAccess extends ChangeNotifier {
  InstallationAccess(
    this.db, {
    Future<bool> Function(String)? verifyPassword,
    DateTime Function()? clock,
    this.authorizeProtectionChange,
    this.onProtectionChanged,
  }) : _verifyPassword = verifyPassword ?? _verifyDefault,
       _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final Future<bool> Function(String) _verifyPassword;
  final DateTime Function() _clock;
  final void Function()? authorizeProtectionChange, onProtectionChanged;
  Future<void>? _loading, _closing;
  Future<void> _queue = Future.value();
  bool _loaded = false, _closed = false;
  bool _introductionSeen = false, _adultVerified = false;
  bool _protectContentFilter = false;
  int _failures = 0;
  DateTime? _retryAfter;

  bool get introductionSeen => _introductionSeen;
  bool get adultVerified => _loaded && _adultVerified;
  bool get protectContentFilter => !_loaded || _protectContentFilter;

  static Future<bool> _verifyDefault(String input) =>
      const PasswordHasher().verify(input, const {
        'algorithm': PasswordHasher.algorithm,
        'salt': 'S6RCK1+ziF7T7C3DLkwLeg==',
        'hash': 'T+lXyfhCdTAdIXNGplAWrbcF6Jn83z7LW46xjHwPlLg=',
      });

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final rows = await db.rows('SELECT value FROM app_meta WHERE key=?', [
      installationAccessKey,
    ]);
    if (rows.isEmpty) throw const FormatException('本机验证状态缺失，无法继续');
    final raw = jsonDecode(rows.single['value'] as String);
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['introductionSeen'] is! bool ||
        raw['adultVerified'] is! bool ||
        raw['protectContentFilter'] is! bool ||
        raw['failures'] is! int ||
        (raw['failures'] as int) < 0 ||
        (raw['retryAfter'] != null && raw['retryAfter'] is! int)) {
      throw const FormatException('本机验证状态损坏，无法继续');
    }
    _introductionSeen = raw['introductionSeen'] as bool;
    _adultVerified = raw['adultVerified'] as bool;
    _protectContentFilter = raw['protectContentFilter'] as bool;
    _failures = (raw['failures'] as int).clamp(0, 100);
    final retry = raw['retryAfter'] as int?;
    _retryAfter = retry == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(retry);
    _loaded = true;
  }

  void requireAdultAccess() {
    if (_closed) throw const FormatException('应用正在退出');
    if (!adultVerified) throw const FormatException('首次关闭成人过滤需要验证访问密码');
  }

  Future<void> finishIntroduction() => _serialize(() async {
    if (_introductionSeen) return;
    await _save(introductionSeen: true, retryAfter: _retryAfter);
  });

  Future<void> verifyAdultPassword(String input) => _serialize(() async {
    if (_adultVerified) return;
    final now = _clock();
    if (_retryAfter != null && now.isBefore(_retryAfter!)) {
      throw const FormatException('验证失败次数过多，请稍后再试');
    }
    if (input.isEmpty || input.length > 128 || !await _verifyPassword(input)) {
      final failures = (_failures + 1).clamp(0, 100);
      final retry = failures < 5
          ? null
          : now.add(
              Duration(
                seconds: (30 * (1 << (failures - 5).clamp(0, 4))).clamp(
                  30,
                  300,
                ),
              ),
            );
      await _save(failures: failures, retryAfter: retry);
      throw const FormatException('访问密码不正确');
    }
    await _save(adultVerified: true, failures: 0);
  });

  Future<void> setContentFilterProtection(bool value) => _serialize(() async {
    authorizeProtectionChange?.call();
    if (value == _protectContentFilter) return;
    await _save(
      protectContentFilter: value,
      retryAfter: _retryAfter,
      authorize: authorizeProtectionChange,
    );
  });

  Future<void> _serialize(Future<void> Function() action) {
    if (_closed) return Future.error(const FormatException('应用正在退出'));
    final operation = _queue.then((_) async {
      await load();
      if (_closed) throw const FormatException('应用正在退出');
      await action();
    });
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> _save({
    bool? introductionSeen,
    bool? adultVerified,
    bool? protectContentFilter,
    int? failures,
    DateTime? retryAfter,
    void Function()? authorize,
  }) async {
    final state = {
      'version': 1,
      'introductionSeen': introductionSeen ?? _introductionSeen,
      'adultVerified': adultVerified ?? _adultVerified,
      'protectContentFilter': protectContentFilter ?? _protectContentFilter,
      'failures': failures ?? _failures,
      'retryAfter': retryAfter?.millisecondsSinceEpoch,
    };
    await db.atomic(() async {
      // A queued write may outlive the credentials or policy it authorized.
      authorize?.call();
      await db.customStatement('INSERT OR REPLACE INTO app_meta VALUES(?,?)', [
        installationAccessKey,
        jsonEncode(state),
      ]);
    }, tables: const {'app_meta'});
    _introductionSeen = state['introductionSeen'] as bool;
    _adultVerified = state['adultVerified'] as bool;
    final protectionChanged =
        _protectContentFilter != state['protectContentFilter'];
    _protectContentFilter = state['protectContentFilter'] as bool;
    _failures = state['failures'] as int;
    _retryAfter = retryAfter;
    if (protectionChanged) onProtectionChanged?.call();
    if (!_closed) notifyListeners();
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    await _queue;
    dispose();
  }
}
