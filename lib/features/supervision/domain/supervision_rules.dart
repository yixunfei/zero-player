import 'content_classification.dart';

enum SensitiveOperation { channels, settings, restore, export, supervision }

final class BlockedChannel {
  const BlockedChannel(this.key, this.label);
  final String key, label;
  Map<String, String> toJson() => {'key': key, 'label': label};
  factory BlockedChannel.fromJson(Map value) {
    final key = value['key'], label = value['label'];
    if (key is! String ||
        label is! String ||
        key.length > 256 ||
        label.isEmpty ||
        label.length > 160 ||
        !RegExp(r'^(vod|live|radio):.+$').hasMatch(key)) {
      throw const FormatException('监管频道规则无效');
    }
    return BlockedChannel(key, label);
  }
}

final class SupervisionRules {
  SupervisionRules({
    Iterable<BlockedChannel> channels = const [],
    Iterable<String> keywords = const [],
  }) : channels = List.unmodifiable(channels),
       keywords = List.unmodifiable(keywords) {
    if (this.channels.length > 500 || this.keywords.length > 200) {
      throw const FormatException('最多屏蔽 500 个频道和 200 个关键词');
    }
    for (final channel in this.channels) {
      BlockedChannel.fromJson(channel.toJson());
    }
    for (final word in this.keywords) {
      if (word.length > 80 || normalizeContent(word).isEmpty) {
        throw const FormatException('关键词需包含文字或数字，最多 80 字符');
      }
    }
    _keys = this.channels.map((c) => c.key).toSet();
    _words = this.keywords.map(normalizeContent).toSet().toList();
  }
  final List<BlockedChannel> channels;
  final List<String> keywords;
  late final Set<String> _keys;
  late final List<String> _words;
  bool blocksKey(String key) => _keys.contains(key);
  bool blocksText(String value) {
    if (_words.isEmpty) return false;
    final normalized = normalizeContent(value);
    return _words.any(normalized.contains);
  }

  Map<String, Object> toJson() => {
    'channels': channels.map((c) => c.toJson()).toList(),
    'keywords': keywords,
  };
  factory SupervisionRules.fromJson(Map value) => SupervisionRules(
    channels: (value['channels'] as List).map(
      (e) => BlockedChannel.fromJson(e as Map),
    ),
    keywords: List<String>.from(value['keywords'] as List),
  );
}

final class ContentBlocked extends FormatException {
  const ContentBlocked([super.message = '内容已被成人过滤或监管规则屏蔽']);
}
