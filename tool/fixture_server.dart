import 'dart:io';

import 'package:path/path.dart' as p;

/// Development-only server. The application does not depend on this service.
Future<void> main(List<String> args) async {
  final directory = Directory(
    args.isEmpty ? 'test_support/generated' : args[0],
  ).absolute;
  final port = args.length > 1 ? int.parse(args[1]) : 9763;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Synthetic fixtures: http://127.0.0.1:$port/master.m3u8');
  await for (final request in server) {
    try {
      final parts = request.uri.pathSegments;
      final candidate = p.normalize(p.joinAll([directory.path, ...parts]));
      if (!p.isWithin(directory.path, candidate)) {
        request.response.statusCode = 403;
      } else {
        await serveFile(request, File(candidate));
      }
    } catch (_) {
      request.response.statusCode = 500;
    } finally {
      await request.response.close();
    }
  }
}

Future<void> serveFile(HttpRequest request, File file) async {
  if (!await file.exists()) {
    request.response.statusCode = 404;
    return;
  }
  final length = await file.length();
  final type = switch (p.extension(file.path)) {
    '.m3u8' => 'application/vnd.apple.mpegurl',
    '.mp4' || '.m4s' => 'video/mp4',
    '.ts' => 'video/mp2t',
    '.flv' => 'video/x-flv',
    _ => 'application/octet-stream',
  };
  request.response.headers.set(HttpHeaders.contentTypeHeader, type);
  request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  var start = 0;
  var end = length - 1;
  final range = request.headers.value(HttpHeaders.rangeHeader);
  if (range != null) {
    final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
    if (match == null) {
      request.response.statusCode = 416;
      return;
    }
    start = int.parse(match[1]!);
    end = match[2]!.isEmpty ? end : int.parse(match[2]!);
    if (start > end || end >= length) {
      request.response.statusCode = 416;
      return;
    }
    request.response.statusCode = 206;
    request.response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/$length',
    );
  }
  request.response.contentLength = end - start + 1;
  if (request.method != 'HEAD') {
    await request.response.addStream(file.openRead(start, end + 1));
  }
}
