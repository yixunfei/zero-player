import 'dart:async';
import 'dart:io';

import 'cancellation_token.dart';
import 'header_policy.dart';
import 'request_scheduler.dart';

final class HttpPayload {
  const HttpPayload(this.uri, this.response, this.body);
  final Uri uri;
  final HttpClientResponse response;
  final Stream<List<int>> body;
}

/// Shared transport with scoped headers, cancellation and a bounded scheduler.
/// Consumers must subscribe to or cancel the response body to release a permit.
final class MediaHttpClient {
  MediaHttpClient({
    this.timeout = const Duration(seconds: 15),
    RequestScheduler? scheduler,
  }) : _scheduler =
           scheduler ?? RequestScheduler(globalLimit: 20, playbackReserve: 2),
       _ownsScheduler = scheduler == null {
    _client.connectionTimeout = timeout;
    _client.autoUncompress = false;
    _client.maxConnectionsPerHost = 4;
    _client.idleTimeout = const Duration(seconds: 20);
    _client.userAgent = 'ZeroPlayer/0.1';
  }
  final Duration timeout;
  final RequestScheduler _scheduler;
  final bool _ownsScheduler;
  final HttpClient _client = HttpClient();

  Future<HttpPayload> open(
    Uri uri, {
    required HeaderPolicy policy,
    String? range,
    String? ifRange,
    CancellationToken? cancellation,
    RequestPriority priority = RequestPriority.playback,
    void Function(bool active)? onActivity,
  }) async {
    final initialOrigin = HeaderPolicy.origin(uri);
    for (var redirects = 0; redirects <= 5; redirects++) {
      cancellation?.check();
      if (!{'http', 'https'}.contains(uri.scheme) || uri.userInfo.isNotEmpty) {
        throw const FormatException(
          'Only HTTP(S) URLs without userinfo allowed',
        );
      }
      onActivity?.call(false);
      final permit = await _scheduler.acquire(
        uri,
        priority: priority,
        cancellation: cancellation,
      );
      HttpClientRequest? request;
      void Function()? remove;
      try {
        onActivity?.call(true);
        cancellation?.check();
        request = await _createRequest(uri, cancellation);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        policy.forUri(uri).forEach(request.headers.set);
        if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
        if (ifRange != null && HeaderPolicy.origin(uri) == initialOrigin) {
          request.headers.set(HttpHeaders.ifRangeHeader, ifRange);
        }
        remove = cancellation?.listen(
          () => request!.abort(const RequestCancelled()),
        );
        cancellation?.check();
        final response = await request.close().timeout(timeout);
        if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await _body(
            response,
            request,
            remove,
            cancellation,
            permit,
          ).take(0).drain<void>();
          if (location == null) throw const HttpException('Missing Location');
          uri = uri.resolve(location);
          continue;
        }
        return HttpPayload(
          uri,
          response,
          _body(response, request, remove, cancellation, permit),
        );
      } catch (_) {
        request?.abort();
        remove?.call();
        permit.release();
        rethrow;
      }
    }
    throw const HttpException('Redirect limit exceeded');
  }

  Future<HttpClientRequest> _createRequest(
    Uri uri,
    CancellationToken? token,
  ) async {
    final result = Completer<HttpClientRequest>();
    var abandoned = false;
    final remove = token?.listen(() {
      abandoned = true;
      if (!result.isCompleted) result.completeError(const RequestCancelled());
    });
    unawaited(
      _client
          .getUrl(uri)
          .then(
            (request) {
              if (abandoned) {
                request.abort();
              } else {
                result.complete(request);
              }
            },
            onError: (Object error, StackTrace stack) {
              if (!result.isCompleted) result.completeError(error, stack);
            },
          ),
    );
    try {
      return await result.future.timeout(timeout);
    } finally {
      abandoned = true;
      remove?.call();
    }
  }

  Stream<List<int>> _body(
    HttpClientResponse response,
    HttpClientRequest request,
    void Function()? remove,
    CancellationToken? cancellation,
    RequestPermit permit,
  ) {
    StreamSubscription<List<int>>? upstream;
    late final StreamController<List<int>> body;
    void release() {
      remove?.call();
      permit.release();
    }

    body = StreamController<List<int>>(
      onListen: () {
        upstream = response
            .timeout(timeout)
            .listen(
              (chunk) {
                if (cancellation?.isCancelled == true) {
                  body.addError(const RequestCancelled());
                } else {
                  body.add(chunk);
                }
              },
              onError: (Object error, StackTrace stack) =>
                  body.addError(error, stack),
              onDone: () {
                release();
                body.close();
              },
            );
      },
      onPause: () => upstream?.pause(),
      onResume: () => upstream?.resume(),
      onCancel: () async {
        // Rejected/partial bodies must cancel the actual upstream subscription,
        // including a take(0) consumer which never reads a payload chunk.
        request.abort();
        try {
          await upstream?.cancel();
        } finally {
          release();
        }
      },
    );
    remove?.call();
    remove = cancellation?.listen(() {
      if (!body.isClosed) body.addError(const RequestCancelled());
      request.abort(const RequestCancelled());
    });
    return body.stream;
  }

  void close() {
    _client.close(force: true);
    if (_ownsScheduler) _scheduler.close();
  }
}
