import 'dart:convert';
import '../../../core/network/cancellation_token.dart';
import '../data/live_audit_defaults.dart';
import '../data/live_health_repository.dart';
import '../domain/channel_probe_signature.dart';
import '../domain/live_channel.dart';
import 'live_probe.dart';

/// Applies the bundled evidence, then verifies changed or failed channels on update.
final class ChannelPreflight {
  ChannelPreflight(this.defaults, this.health, this.probe);
  final LiveAuditDefaults defaults;
  final LiveHealthRepository health;
  final LiveProbe probe;

  Future<void> prepare(List<LiveChannel> channels) async {
    final entries = await defaults.entries;
    if (!defaults.passedOnly && entries.isEmpty) return;
    await health.db.transaction(
      () => defaults.apply(
        health.db,
        channels,
        entries,
        canEnable: health.canEnable?.call() ?? true,
      ),
    );
  }

  Future<void> refresh(
    List<LiveChannel> channels,
    CancellationToken? caller,
  ) async {
    await prepare(channels);
    final token = caller ?? CancellationToken();
    final states = {
      for (final row in await health.db.rows(
        "SELECT key,value FROM app_meta WHERE key GLOB 'live_state:*'",
      ))
        (row['key'] as String).substring(11): _state(row['value']),
    };
    final queue = channels.where((c) {
      final state = states[c.id];
      return state?['removed'] != true &&
          (state?['pendingValidation'] == true ||
              state?['requestSignature'] != channelProbeSignature(c) ||
              state?['availability'] != 'responding' ||
              DateTime.now().millisecondsSinceEpoch -
                      (state?['checkedAt'] is int
                          ? state!['checkedAt'] as int
                          : 0) >
                  const Duration(hours: 24).inMilliseconds);
    }).toList();
    await health.db.transaction(() async {
      for (final channel in queue) {
        final old = states[channel.id] ?? {};
        if (old['preflight'] == true) continue;
        await health.db.customStatement(
          'INSERT OR REPLACE INTO app_meta VALUES(?,?)',
          [
            'live_state:${channel.id}',
            jsonEncode({
              ...old,
              'preflight': true,
              'enabled': false,
              'autoDisabled': true,
              'pendingValidation': true,
              'signature': channel.urls.join('|'),
              'requestSignature': channelProbeSignature(channel),
              'userDisabled':
                  old['userDisabled'] == true ||
                  old['enabled'] == false && old['autoDisabled'] != true,
            }),
          ],
        );
      }
    });
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < queue.length && !token.isCancelled) {
        await probe.check(queue[cursor++], token);
      }
    }

    await Future.wait(List.generate(queue.length.clamp(0, 8), (_) => worker()));
    token.check();
  }

  Map _state(Object? value) {
    try {
      final decoded = jsonDecode(value as String);
      return decoded is Map ? decoded : {};
    } catch (_) {
      return {};
    }
  }
}
