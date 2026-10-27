import 'dart:convert';
import '../../../app/app_fonts.dart';

/// Validate payload semantics before the database transaction begins. A valid
/// SQL string alone must not turn malformed JSON into a persistent startup fault.
void validateBackupRecord(String table, Map row) {
  if (table == 'app_meta') {
    if ((row['key'] as String).startsWith('live_list_enabled:')) {
      if (!{'true', 'false'}.contains(row['value'])) {
        throw const FormatException('直播订阅启停字段无效');
      }
      return;
    }
    if ((row['key'] as String).startsWith('live_state:')) {
      _liveState(jsonDecode(row['value'] as String));
      return;
    }
    if (!(row['key'] as String).startsWith('live_headers:')) {
      throw const FormatException('备份包含未知的直播元数据');
    }
    validateBackupRecord('live_headers', {'headers': row['value']});
    return;
  }
  for (final key in ['enabled', 'suppressed', 'manual', 'paused', 'favorite']) {
    if (row.containsKey(key) && !{0, 1}.contains(row[key])) {
      throw const FormatException('布尔字段不正确');
    }
  }
  for (final key in [
    'position_ms',
    'duration_ms',
    'start_ms',
    'end_ms',
    'refresh_hours',
  ]) {
    if (row.containsKey(key) && (row[key] as int) < 0) {
      throw const FormatException('数值超出范围');
    }
  }
  if (row.containsKey('headers')) {
    final headers = jsonDecode(row['headers'] as String);
    if (headers is! Map ||
        headers.length > 50 ||
        headers.entries.any(
          (e) =>
              e.key is! String ||
              e.value is! String ||
              '${e.key}${e.value}'.contains(RegExp(r'[\r\n]')),
        )) {
      throw const FormatException('请求头格式无效');
    }
  }
  for (final key in ['url', 'endpoint', 'epg_url']) {
    if (row[key] != null) _url(row[key]);
  }
  if (table == 'sources' &&
      (!{'cms', 'kanju', 'macCmsHtml'}.contains(row['kind']) ||
          !{'unknown', 'general', 'adult'}.contains(row['classification']))) {
    throw const FormatException('来源类型或分类无效');
  }
  if (table == 'live_channels') {
    final urls = jsonDecode(row['urls'] as String);
    if (urls is! List || urls.isEmpty || urls.length > 100) {
      throw const FormatException('频道地址无效');
    }
    for (final url in urls) {
      _url(url);
    }
  }
  if (table == 'settings') {
    _setting(row['key'] as String, jsonDecode(row['value'] as String));
  }
  if (table == 'skip_marks' &&
      (row['end_ms'] as int) > (row['duration_ms'] as int)) {
    throw const FormatException('片段超过视频时长');
  }
}

void _liveState(Object? value) {
  if (value is! Map ||
      value.keys.any(
        (key) => !{
          'enabled',
          'availability',
          'checkedAt',
          'latencyMs',
          'message',
          'preferredUrl',
          'signature',
        }.contains(key),
      ) ||
      (value.containsKey('enabled') && value['enabled'] is! bool) ||
      (value.containsKey('availability') &&
          !{
            'unknown',
            'responding',
            'unavailable',
            'inconclusive',
          }.contains(value['availability']))) {
    throw const FormatException('直播状态无效');
  }
  for (final key in ['checkedAt', 'latencyMs']) {
    if (value[key] != null && (value[key] is! int || (value[key] as int) < 0)) {
      throw const FormatException('直播检测数值无效');
    }
  }
  for (final key in ['message', 'signature']) {
    if (value[key] != null && value[key] is! String) {
      throw const FormatException('直播状态字段无效');
    }
  }
  if (value['preferredUrl'] != null) _url(value['preferredUrl']);
}

void _url(Object? value) {
  final uri = value is String ? Uri.tryParse(value) : null;
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('备份含无效的 HTTP(S) 地址');
  }
}

void _setting(String key, Object? value) {
  final choices = <String, Set<String>>{
    'font': appFontLabels.keys.toSet(),
    'theme': {'cinema', 'dark', 'light', 'system'},
    'mode': {'auto', 'television'},
    'recommendation': {'douban', 'bangumi', 'hot', 'off'},
    'homeLayout': {'single', 'aggregate'},
  };
  if (choices.containsKey(key)) {
    if (!choices[key]!.contains(value)) throw const FormatException('设置选项无效');
  } else if (key == 'manualLoadCount') {
    if (value is! int || value < 12 || value > 240) {
      throw const FormatException('加载数量无效');
    }
  } else if (key == 'homeChannel') {
    if (value is! String || value.length > 128) {
      throw const FormatException('默认频道无效');
    }
  } else if ({
    'searchConcurrency',
    'probeConcurrency',
    'downloadConcurrency',
  }.contains(key)) {
    final max = key == 'searchConcurrency'
        ? 16
        : key == 'probeConcurrency'
        ? 6
        : 4;
    if (value is! int || value < 1 || value > max) {
      throw const FormatException('并发设置无效');
    }
  } else if (key == 'prefetchSegments') {
    if (value is! int || value < 0 || value > 10) {
      throw const FormatException('预取设置无效');
    }
  } else if ({'cacheMiB', 'episodeCacheMiB', 'downloadMiB'}.contains(key)) {
    if (value is! int || value < 64 || value > 1048576) {
      throw const FormatException('容量设置无效');
    }
  } else if ({
    'backgroundProbe',
    'startFullscreen',
    'navigationGuideSeen',
    'autoDownloadFallback',
    'multiSourceDownload',
    'gestures',
    'autoplay',
    'cache',
    'skip',
    'adFilter',
    'filterAdult',
    'allowMetered',
    'cacheWhilePaused',
  }.contains(key)) {
    if (value is! bool) throw const FormatException('开关设置无效');
  } else {
    throw const FormatException('未知设置字段');
  }
}
