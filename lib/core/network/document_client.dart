import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cancellation_token.dart';
import 'header_policy.dart';
import 'media_http_client.dart';
import 'request_scheduler.dart';
import 'network_budget.dart';

enum FailureKind {
  cancelled,
  timeout,
  network,
  http,
  invalid,
  unsupported,
  storage,
}

final class RemoteFailure implements Exception {
  const RemoteFailure(this.kind, this.message, {this.status, this.retryAfter});
  final FailureKind kind;
  final String message;
  final int? status;
  final Duration? retryAfter;
  @override
  String toString() => message;
}

final class Document {
  const Document(this.uri, this.bytes);
  final Uri uri;
  final List<int> bytes;
  String get text => utf8.decode(bytes).replaceFirst('\uFEFF', '');
  Object? get json => jsonDecode(text);
}

final class DocumentClient {
  const DocumentClient(this.http);
  final MediaHttpClient http;

  Future<Document> get(
    Uri uri, {
    Map<String, String> headers = const {},
    int maxBytes = 2 * 1024 * 1024,
    CancellationToken? cancellation,
    RequestPriority priority = RequestPriority.interactive,
    bool gzip = false,
    void Function(bool active)? onActivity,
    Duration networkTimeout = const Duration(seconds: 25),
  }) async {
    final token = CancellationToken();
    final unlink = cancellation?.listen(token.cancel);
    final budget = NetworkBudget(networkTimeout, token, onActivity: onActivity);
    try {
      for (var attempt = 0; ; attempt++) {
        try {
          return await _getOnce(
            uri,
            headers: headers,
            maxBytes: maxBytes,
            cancellation: token,
            priority: priority,
            gzip: gzip,
            onActivity: budget.activity,
          );
        } on RemoteFailure catch (failure) {
          final transient =
              failure.kind == FailureKind.network ||
              failure.kind == FailureKind.timeout ||
              {429, 502, 503, 504}.contains(failure.status);
          if (!transient ||
              attempt >= 1 ||
              token.isCancelled ||
              (failure.retryAfter != null &&
                  failure.retryAfter! > const Duration(seconds: 3))) {
            rethrow;
          }
          budget.activity(false);
          await _delay(
            failure.retryAfter ?? const Duration(milliseconds: 400),
            token,
          );
        }
      }
    } on RequestCancelled {
      throw RemoteFailure(
        cancellation?.isCancelled == true
            ? FailureKind.cancelled
            : FailureKind.timeout,
        cancellation?.isCancelled == true ? '操作已取消' : '请求超时',
      );
    } on RemoteFailure {
      if (token.isCancelled && cancellation?.isCancelled != true) {
        throw const RemoteFailure(FailureKind.timeout, '请求超时');
      }
      rethrow;
    } finally {
      budget.dispose();
      unlink?.call();
    }
  }

  Future<void> _delay(Duration duration, CancellationToken token) async {
    token.check();
    final done = Completer<void>();
    final timer = Timer(
      duration > const Duration(seconds: 3)
          ? const Duration(seconds: 3)
          : duration,
      () => done.complete(),
    );
    final unlink = token.listen(() {
      if (!done.isCompleted) done.completeError(const RequestCancelled());
    });
    try {
      await done.future;
    } finally {
      timer.cancel();
      unlink();
    }
  }

  Future<Document> _getOnce(
    Uri uri, {
    Map<String, String> headers = const {},
    int maxBytes = 2 * 1024 * 1024,
    CancellationToken? cancellation,
    RequestPriority priority = RequestPriority.interactive,
    bool gzip = false,
    void Function(bool active)? onActivity,
  }) async {
    try {
      final response = await http.open(
        uri,
        policy: HeaderPolicy({uri: headers}),
        cancellation: cancellation,
        priority: priority,
        onActivity: onActivity,
      );
      if (response.response.statusCode != 200) {
        await response.body.take(0).drain<void>();
        throw RemoteFailure(
          FailureKind.http,
          '服务返回错误 ${response.response.statusCode}',
          status: response.response.statusCode,
          retryAfter: _retryAfter(
            response.response.headers.value('retry-after'),
          ),
        );
      }
      final compressed =
          response.response.headers.value('content-encoding') == 'gzip' || gzip;
      final body = compressed
          ? GZipCodec().decoder.bind(response.body)
          : response.body;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const RemoteFailure(FailureKind.invalid, '文件超过大小限制');
        }
        bytes.add(chunk);
      }
      return Document(response.uri, bytes.takeBytes());
    } on RequestCancelled {
      throw const RemoteFailure(FailureKind.cancelled, '操作已取消');
    } on TimeoutException {
      throw const RemoteFailure(FailureKind.timeout, '请求超时，请稍后重试');
    } on SocketException {
      throw const RemoteFailure(FailureKind.network, '无法连接，请检查网络和来源地址');
    } on HttpException {
      throw const RemoteFailure(FailureKind.network, '来源连接中断或响应不完整');
    } on HandshakeException {
      throw const RemoteFailure(FailureKind.network, '来源的安全连接验证失败');
    } on FormatException {
      throw const RemoteFailure(FailureKind.invalid, '来源数据格式不正确');
    }
  }
}

Duration? _retryAfter(String? value) {
  if (value == null) return null;
  final seconds = int.tryParse(value);
  if (seconds != null) return Duration(seconds: seconds.clamp(0, 86400));
  try {
    final wait = HttpDate.parse(value).difference(DateTime.now());
    return wait.isNegative ? Duration.zero : wait;
  } catch (_) {
    return null;
  }
}
