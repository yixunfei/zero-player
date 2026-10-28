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
    if (size == 0 ||
        match == null ||
        (match[1]!.isEmpty && match[2]!.isEmpty)) {
      _rejectRange(request.response, size);
      return;
    }
    if (match[1]!.isEmpty) {
      start = size - _boundedOffset(match[2]!, size);
    } else {
      start = _boundedOffset(match[1]!, size);
      if (match[2]!.isNotEmpty) end = _boundedOffset(match[2]!, size - 1);
    }
    if (start > end || start >= size) {
      _rejectRange(request.response, size);
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

int _boundedOffset(String digits, int limit) {
  // A valid HTTP range can exceed Dart's native integer width. Compare before
  // converting so oversized ends/suffixes still serve the available bytes.
  final value = BigInt.parse(digits);
  return value > BigInt.from(limit) ? limit : value.toInt();
}

void _rejectRange(HttpResponse response, int size) {
  response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
  response.headers.set('content-range', 'bytes */$size');
}
