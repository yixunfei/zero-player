import 'dart:io';

Future<void> serveLocalFile(
  HttpRequest request,
  File file, {
  String? contentType,
}) async {
  if (!await file.exists()) {
    request.response.statusCode = 404;
    return;
  }
  final size = await file.length();
  var start = 0;
  var end = size - 1;
  final range = request.headers.value('range');
  if (range != null) {
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
    if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
      request.response.statusCode = 416;
      return;
    }
    if (match[1]!.isEmpty) {
      start = (size - int.parse(match[2]!)).clamp(0, size);
    } else {
      start = int.parse(match[1]!);
      if (match[2]!.isNotEmpty) end = int.parse(match[2]!).clamp(0, size - 1);
    }
    if (start > end || start >= size) {
      request.response.statusCode = 416;
      request.response.headers.set('content-range', 'bytes */$size');
      return;
    }
    request.response.statusCode = 206;
    request.response.headers.set('content-range', 'bytes $start-$end/$size');
  }
  request.response.headers.set('accept-ranges', 'bytes');
  if (contentType != null) {
    request.response.headers.set('content-type', contentType);
  }
  request.response.contentLength = end - start + 1;
  if (request.method != 'HEAD') {
    await request.response.addStream(file.openRead(start, end + 1));
  }
}
