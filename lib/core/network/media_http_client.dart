import 'dart:async';
import 'dart:io';

import 'cancellation_token.dart';
import 'header_policy.dart';
import 'request_scheduler.dart';
import 'request_trace.dart';
import 'network_target_policy.dart';

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
    this.maxConnectionsPerHost = 4,
    RequestScheduler? scheduler,
    bool allowPrivateNetworks = false,
    bool Function(Uri)? allowLanOrigin,
  }) : _scheduler =
           scheduler ?? RequestScheduler(globalLimit: 20, playbackReserve: 2),
       _ownsScheduler = scheduler == null,
       targetPolicy = NetworkTargetPolicy(
         allowPrivateNetworks: allowPrivateNetworks,
         allowLanOrigin: allowLanOrigin,
       ) {
    _configureClient();
  }

  void _configureClient() {
    _client.connectionTimeout = timeout;
    _client.connectionFactory = targetPolicy.connect;
    _client.findProxy = (_) => 'DIRECT';
    _client.autoUncompress = false;
    _client.maxConnectionsPerHost = maxConnectionsPerHost;
    _client.idleTimeout = const Duration(seconds: 20);
    _client.userAgent = 'ZeroPlayer/0.1';
  }

  final Duration timeout;
  final int maxConnectionsPerHost;
  final NetworkTargetPolicy targetPolicy;
  final RequestScheduler _scheduler;
  final bool _ownsScheduler;
  HttpClient _client = HttpClient();
  bool _closed = false;

  void resetConnections() {
    if (_closed) return;
    _client.close(force: true);
    _client = HttpClient();
    _configureClient();
  }

  Future<HttpPayload> open(
    Uri uri, {
    required HeaderPolicy policy,
    String method = 'GET',
    List<int>? body,
    String? range,
    String? ifRange,
    CancellationToken? cancellation,
    RequestPriority priority = RequestPriority.playback,
    void Function(bool active)? onActivity,
  }) async {
    if (!{'GET', 'POST'}.contains(method) ||
        (body != null && (method != 'POST' || body.length > 65536))) {
      throw const FormatException('不支持的请求方式或请求体过大');
    }
    final initialOrigin = HeaderPolicy.origin(uri);
    for (var redirects = 0; redirects <= 5; redirects++) {
      cancellation?.check();
      targetPolicy.validateAccess(
        uri,
        originalOrigin:
            HeaderPolicy.origin(uri) == initialOrigin &&
            policy.containsOrigin(uri),
      );
      onActivity?.call(false);
      final permit = await _scheduler.acquire(
        uri,
        priority: priority,
        cancellation: cancellation,
      );
      HttpClientRequest? request;
      void Function()? remove;
      final watch = Stopwatch();
      var recorded = false;
      try {
        onActivity?.call(true);
        watch.start();
        cancellation?.check();
        request = await _createRequest(uri, cancellation, method);
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
        if (body != null) {
          request.contentLength = body.length;
          request.add(body);
        }
        final response = await request.close().timeout(timeout);
        _recordResponse(
          uri,
          watch.elapsedMilliseconds,
          request.headers,
          response,
        );
        recorded = true;
        if (method == 'GET' &&
            {301, 302, 303, 307, 308}.contains(response.statusCode)) {
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
      } catch (error) {
        if (!recorded) {
          recordRequestTrace(
            uri: uri,
            elapsedMs: watch.elapsedMilliseconds,
            requestHeaders: policy.forUri(uri),
            error: error.runtimeType.toString(),
          );
        }
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
    String method,
  ) async {
    final result = Completer<HttpClientRequest>();
    var abandoned = false;
    final remove = token?.listen(() {
      abandoned = true;
      if (!result.isCompleted) result.completeError(const RequestCancelled());
    });
    unawaited(
      _client
          .openUrl(method, uri)
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

  void _recordResponse(
    Uri uri,
    int elapsed,
    HttpHeaders headers,
    HttpClientResponse response,
  ) => recordRequestTrace(
    uri: uri,
    elapsedMs: elapsed,
    requestHeaders: diagnosticHttpHeaders(headers),
    status: response.statusCode,
    responseHeaders: {
      for (final name in [
        'content-type',
        'content-length',
        'server',
        'location',
      ])
        name: ?response.headers.value(name),
    },
  );

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
    _closed = true;
    _client.close(force: true);
    if (_ownsScheduler) _scheduler.close();
  }
}
