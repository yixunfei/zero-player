import '../../../media/content_filter/fingerprints/feature_rule.dart';
import 'dart:convert';
import '../domain/settings_validation.dart';
import '../../radio/data/radio_backup_validation.dart';

/// Validate payload semantics before the database transaction begins. A valid
/// SQL string alone must not turn malformed JSON into a persistent startup fault.
void validateBackupRecord(String table, Map row) {
  if (table == 'app_meta') {
    _appMetadata(row);
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
    if (table == 'live_lists' && key == 'epg_url' && row[key] == '') continue;
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
    validateSetting(row['key'] as String, jsonDecode(row['value'] as String));
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
          'removed',
          'availability',
          'checkedAt',
          'latencyMs',
          'message',
          'preferredUrl',
          'signature',
          'resolution',
          'languages',
          'preflight',
          'userDisabled',
          'autoDisabled',
          'pendingValidation',
          'requestSignature',
          'verifiedUrls',
        }.contains(key),
      ) ||
      (value.containsKey('enabled') && value['enabled'] is! bool) ||
      (value.containsKey('removed') && value['removed'] is! bool) ||
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
  for (final key in [
    'preflight',
    'userDisabled',
    'autoDisabled',
    'pendingValidation',
  ]) {
    if (value.containsKey(key) && value[key] is! bool) {
      throw const FormatException('频道预检状态无效');
    }
  }
  if (value['requestSignature'] != null &&
      (value['requestSignature'] is! String ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(value['requestSignature'] as String))) {
    throw const FormatException('频道请求摘要无效');
  }
  if (value['verifiedUrls'] != null) {
    if (value['verifiedUrls'] is! List ||
        (value['verifiedUrls'] as List).length > 100) {
      throw const FormatException('已验证线路无效');
    }
    for (final url in value['verifiedUrls'] as List) {
      _url(url);
    }
  }
  _mediaMetadata(value);
}

void _mediaMetadata(Map value) {
  if (value['resolution'] != null &&
      (value['resolution'] is! String ||
          (value['resolution'] as String).length > 50)) {
    throw const FormatException('直播分辨率字段无效');
  }
  for (final key in ['languages', 'countries', 'categories']) {
    final list = value[key];
    if (list != null &&
        (list is! List ||
            list.length > 100 ||
            list.any((v) => v is! String || v.length > 200))) {
      throw const FormatException('直播分类字段无效');
    }
  }
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

void _appMetadata(Map row) {
  if ((row['key'] as String).startsWith('content_label:')) {
    _contentLabel(row);
    return;
  }
  if ((row['key'] as String).startsWith('filter_feature:')) {
    final value = row['value'] as String;
    if (value.length > 100000) throw const FormatException('特征数据过大');
    final rule = FeatureRule.fromJson(jsonDecode(value));
    if (row['key'] != 'filter_feature:${rule.id}') {
      throw const FormatException('特征标识不一致');
    }
    return;
  }
  if ((row['key'] as String).startsWith('source_favorite:')) {
    if (!RegExp(
          r'^source_favorite:[a-f0-9]{64}$',
        ).hasMatch(row['key'] as String) ||
        !{'true', 'false'}.contains(row['value'])) {
      throw const FormatException('渠道收藏字段无效');
    }
    return;
  }
  if (validateRadioMetadata(row['key'] as String, row['value'] as String)) {
    return;
  }
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
  if ((row['key'] as String).startsWith('live_metadata:')) {
    final data = jsonDecode(row['value'] as String);
    if (data is! Map ||
        data.keys.any(
          (k) => !{
            'signature',
            'languages',
            'countries',
            'categories',
            'resolution',
          }.contains(k),
        ) ||
        data['signature'] is! String) {
      throw const FormatException('直播元数据无效');
    }
    _mediaMetadata(data);
    return;
  }
  if (!(row['key'] as String).startsWith('live_headers:')) {
    throw const FormatException('备份包含未知的直播元数据');
  }
  validateBackupRecord('live_headers', {'headers': row['value']});
  return;
}

void _contentLabel(Map row) {
  final identity = (row['key'] as String).substring('content_label:'.length);
  final separator = identity.indexOf(':');
  final data = jsonDecode(row['value'] as String);
  const fields = {
    'title',
    'year',
    'category',
    'categoryId',
    'tags',
    'description',
    'director',
    'remarks',
  };
  if (separator <= 0 ||
      separator == identity.length - 1 ||
      data is! Map ||
      data['title'] is! String ||
      data.entries.any(
        (entry) => !fields.contains(entry.key) || entry.value is! String,
      )) {
    throw const FormatException('历史内容分类元数据无效');
  }
}

void validateFeatureCollection(List<Map<String, Object?>> rows) {
  final counts = <String, int>{};
  var total = 0;
  for (final row in rows.where(
    (r) => (r['key'] as String).startsWith('filter_feature:'),
  )) {
    final rule = FeatureRule.fromJson(jsonDecode(row['value'] as String));
    counts[rule.sourceId] = (counts[rule.sourceId] ?? 0) + 1;
    if (++total > 500 || counts[rule.sourceId]! > 100) {
      throw const FormatException('特征数量超限：总计 500 条、每渠道 100 条');
    }
  }
}
