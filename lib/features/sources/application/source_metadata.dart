import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/request_scheduler.dart';
import '../../../core/text/display_text.dart';
import '../data/source_repository.dart';
import '../domain/video_source.dart';

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
      );
      final match = RegExp(
        r'<title[^>]*>([\s\S]*?)</title>',
        caseSensitive: false,
      ).firstMatch(document.text);
      title = _text(match == null ? null : displayText(match[1]!));
      if (title != null &&
          !RegExp(
            r'404|403|502|error|access denied|just a moment',
            caseSensitive: false,
          ).hasMatch(title)) {
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
  return value.trim().substring(0, value.trim().length.clamp(0, 120));
}
