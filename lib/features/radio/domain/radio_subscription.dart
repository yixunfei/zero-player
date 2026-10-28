import '../../sources/domain/video_source.dart';

const builtinRadioUrl =
    'https://raw.githubusercontent.com/popocoding/awesome-m3u/refs/heads/main/radio/cn.m3u';

final class RadioSubscription {
  RadioSubscription({
    required this.name,
    required this.url,
    this.enabled = true,
  }) {
    if (name.trim().isEmpty ||
        !{'http', 'https'}.contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty) {
      throw const FormatException('请填写广播订阅名称和有效 HTTP(S) 地址');
    }
  }
  final String name;
  final Uri url;
  final bool enabled;
  String get id => stableId(url.toString());
  Map<String, Object?> toJson() => {
    'name': name,
    'url': '$url',
    'enabled': enabled,
  };
  factory RadioSubscription.fromJson(Map data) {
    if (data['name'] is! String ||
        data['url'] is! String ||
        data['enabled'] is! bool) {
      throw const FormatException('广播订阅配置无效');
    }
    return RadioSubscription(
      name: data['name'] as String,
      url: Uri.parse(data['url'] as String),
      enabled: data['enabled'] as bool,
    );
  }
}
