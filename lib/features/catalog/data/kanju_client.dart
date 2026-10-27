import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../../../core/network/document_client.dart';
import 'website_transport.dart';

/// Mirrors the public web client's request signing, not account credentials.
final class KanjuClient {
  const KanjuClient(this.transport);
  final WebsiteTransport transport;
  // Public client protocol inspected on 2026-10-27. Rotation fails explicitly.
  static const publicSigningKey =
      '557d0e4ae929f438da6bd84412374e6086b8af09b3fed54bf22601d5bf8c54a0';

  static Map<String, String> signature(
    Uri uri,
    String timestamp,
    String nonce,
  ) {
    final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    final payload = [
      'GET',
      path,
      timestamp,
      nonce,
    ].join(String.fromCharCode(10));
    return {
      'x-ai-movie-timestamp': timestamp,
      'x-ai-movie-nonce': nonce,
      'x-ai-movie-signature': Hmac(
        sha256,
        utf8.encode(publicSigningKey),
      ).convert(utf8.encode(payload)).toString(),
      'Accept': 'application/json',
    };
  }

  Future<Map> get(Uri uri) async {
    transport.requireSameOrigin(uri);
    if (!uri.path.startsWith('/v1/')) throw const FormatException('接口路径无效');
    final random = Random.secure();
    final nonce = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    try {
      final doc = await transport.get(
        uri,
        headers: signature(
          uri,
          '${DateTime.now().millisecondsSinceEpoch}',
          nonce,
        ),
      );
      final data = doc.json;
      if (data is! Map || data.containsKey('error')) {
        throw const RemoteFailure(FailureKind.invalid, '看剧AI返回了无效数据');
      }
      return data;
    } on RemoteFailure catch (e) {
      if (e.status == 401 || e.status == 403) {
        throw RemoteFailure(
          FailureKind.unsupported,
          '看剧AI要求验证、登录或已更新接口签名，请访问原站或更新适配器',
          status: e.status,
        );
      }
      rethrow;
    }
  }
}
