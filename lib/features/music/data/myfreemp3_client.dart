import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';

/// Implements the site's published browser protocol without running remote JS.
final class MyFreeMp3Client {
  MyFreeMp3Client(this.network, {Uri? endpoint})
    : endpoint = endpoint ?? Uri.parse('https://api.myfreemp3.ink');

  final DocumentClient network;
  final Uri endpoint;
  String? _keyId;
  String? _key;
  int _expiresAt = 0;
  static const headers = {
    'Origin': 'https://myfreemp3.ink',
    'Referer': 'https://myfreemp3.ink/',
    'X-Requested-With': 'XMLHttpRequest',
  };

  Future<void> _bootstrap(CancellationToken? cancellation) async {
    final document = await network.get(
      endpoint.resolve('/api/signing/bootstrap'),
      headers: headers,
      cancellation: cancellation,
      maxBytes: 32 * 1024,
    );
    final data = document.json;
    if (data is! Map ||
        data['key_id'] is! String ||
        data['signing_key'] is! String ||
        data['expires_at'] is! num ||
        (data['signing_key'] as String).isEmpty) {
      throw const FormatException('音乐渠道连接数据已变更，请稍后重试');
    }
    _keyId = data['key_id'] as String;
    _key = data['signing_key'] as String;
    _expiresAt = (data['expires_at'] as num).toInt();
  }

  Future<Document> search(
    String query,
    int page, {
    CancellationToken? cancellation,
  }) async {
    final uri = endpoint.replace(
      pathSegments: ['search', query],
      queryParameters: page > 1 ? {'page': '$page'} : null,
    );
    for (var attempt = 0; ; attempt++) {
      cancellation?.check();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (_key == null || now >= _expiresAt - 45 || attempt > 0) {
        await _bootstrap(cancellation);
      }
      cancellation?.check();
      final stamp = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
      final message =
          '$stamp\nGET\n${Uri.decodeComponent(uri.path)}\n'
          '${uri.hasQuery ? '?${uri.query}' : ''}';
      final signature = Hmac(
        sha256,
        utf8.encode(_key!),
      ).convert(utf8.encode(message)).toString();
      try {
        return await network.get(
          uri,
          headers: {
            ...headers,
            'X-Api-Key-Id': _keyId!,
            'X-Api-Ts': stamp,
            'X-Api-Sig': signature,
          },
          cancellation: cancellation,
        );
      } on RemoteFailure catch (failure) {
        if (failure.status != 403 || attempt != 0) rethrow;
      }
    }
  }
}
