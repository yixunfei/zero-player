import 'dart:async';
import 'dart:io';

final class HttpTestServer {
  HttpTestServer._(this.server);
  final HttpServer server;
  final calls = <String, int>{};
  Uri get baseUri => Uri.parse('http://127.0.0.1:${server.port}/');

  static Future<HttpTestServer> start(
    FutureOr<void> Function(HttpRequest) handle,
  ) async {
    final fixture = HttpTestServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.server.listen((request) async {
      fixture.calls.update(
        request.uri.path,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      try {
        await handle(request);
      } finally {
        await request.response.close();
      }
    });
    return fixture;
  }

  Future<void> close() async {
    await server.close(force: true);
  }
}
