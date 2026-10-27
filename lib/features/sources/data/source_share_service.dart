import 'dart:convert';
import 'dart:io';

/// Invoked only by the explicit publish action after preview. No background
/// publication, account credentials, redirects, or source request headers.
Future<Uri> publishSourceText(Uri endpoint, String text) async {
  if (endpoint.scheme != 'https' ||
      endpoint.host.isEmpty ||
      endpoint.userInfo.isNotEmpty) {
    throw const FormatException('发布服务必须使用 HTTPS');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client
        .postUrl(endpoint)
        .timeout(const Duration(seconds: 15));
    request.followRedirects = false;
    request.headers.contentType = ContentType(
      'text',
      'plain',
      charset: 'utf-8',
    );
    request.add(utf8.encode(text));
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const FormatException('发布服务未接受内容');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > 4096) {
        throw const FormatException('发布返回内容过大');
      }
      bytes.addAll(chunk);
    }
    final result = Uri.tryParse(utf8.decode(bytes).trim());
    if (result == null ||
        result.scheme != 'https' ||
        result.host.isEmpty ||
        result.userInfo.isNotEmpty) {
      throw const FormatException('发布服务未返回有效的 HTTPS 链接');
    }
    return result;
  } finally {
    client.close(force: true);
  }
}
