import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/request_scheduler.dart';
import '../../../core/text/display_text.dart';
import 'package:html/parser.dart' as html;
import '../data/source_repository.dart';
import '../domain/video_source.dart';
import '../domain/source_name.dart';

Future<void> updateSourceMetadata(
  VideoSource source,
  Map data,
  SourceRepository repository,
  DocumentClient network,
  CancellationToken token,
) async {
  final info = data['info'] is Map ? data['info'] as Map : data;
  String? title = _text(info['site_name'] ?? info['title'] ?? info['name']);
  var homepage = Uri.tryParse('${info['site_url'] ?? info['homepage'] ?? ''}');
  if (homepage == null ||
      !{'http', 'https'}.contains(homepage.scheme) ||
      homepage.host.isEmpty ||
      homepage.userInfo.isNotEmpty) {
    homepage = null;
  }
  // A guessed origin is only a fetch target, never presented as a verified site.
  if (title == null && source.siteTitle == null) {
    try {
      final document = await network.get(
        source.endpoint.replace(path: '/', query: '', fragment: ''),
        maxBytes: 256 * 1024,
        cancellation: token,
        priority: RequestPriority.background,
        networkTimeout: const Duration(seconds: 5),
      );
      title = sourceTitleFromHtml(document.text);
      if (title != null) {
        homepage ??= document.uri;
      } else {
        title = null;
      }
    } catch (_) {
      token.check();
    }
  }
  if (title != null || homepage != null) {
    await repository.metadata(source.id, title: title, homepage: homepage);
  }
}

String? _text(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  final text = displayText(value).trim();
  if (text.isEmpty ||
      isGenericSourceTitle(text) ||
      RegExp(
        r'404|403|502|error|access denied|just a moment|页面不存在|访问拒绝|安全验证|域名出售|domain.*sale|parking',
        caseSensitive: false,
      ).hasMatch(text)) {
    return null;
  }
  return text.substring(0, text.length.clamp(0, 120));
}

String? sourceTitleFromHtml(String input) {
  final document = html.parse(input);
  for (final selector in [
    'meta[property="og:site_name"]',
    'meta[name="application-name"]',
  ]) {
    final value = _text(
      document.querySelector(selector)?.attributes['content'],
    );
    if (value != null) return value;
  }
  final title = _text(document.querySelector('title')?.text);
  if (title == null) return null;
  final first = title.split(RegExp(r'\s*[-_|｜]\s*')).first.trim();
  return first.length >= 2 ? first : title;
}
