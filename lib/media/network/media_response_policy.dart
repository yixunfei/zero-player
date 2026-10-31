import 'dart:convert';
import 'dart:typed_data';

/// A media endpoint never becomes a document viewer or playlist launcher.
void validateMediaType(String? contentType) {
  final type = (contentType ?? '').split(';').first.trim().toLowerCase();
  if ((type.startsWith('text/') && type != 'text/plain') ||
      type.contains('html') ||
      type.contains('javascript') ||
      type.contains('json') ||
      type.contains('xml') ||
      type.contains('x-msdownload') ||
      type.contains('x-dosexec')) {
    throw const FormatException('来源返回网页、脚本或非媒体内容，已拦截');
  }
}

Stream<List<int>> guardMediaBody(
  Stream<List<int>> source, {
  bool inspectPrefix = true,
}) async* {
  if (!inspectPrefix) {
    yield* source;
    return;
  }
  final prefix = BytesBuilder(copy: false);
  var checked = false;
  await for (final chunk in source) {
    if (checked) {
      yield chunk;
      continue;
    }
    prefix.add(chunk);
    if (prefix.length < 512) continue;
    final bytes = prefix.takeBytes();
    _validatePrefix(bytes);
    checked = true;
    yield bytes;
  }
  if (!checked && prefix.length > 0) {
    final bytes = prefix.takeBytes();
    _validatePrefix(bytes);
    yield bytes;
  }
}

bool startsMediaEntity(String? contentRange, {String? requestedRange}) {
  // An unsolicited or malformed Content-Range must not disable inspection.
  final response = RegExp(
    r'^bytes (\d+)-(\d+)/(?:\d+|\*)$',
  ).firstMatch(contentRange ?? '');
  if (response == null || requestedRange == null) return true;
  final start = int.tryParse(response[1]!);
  if (start == null || start == 0) return true;
  final request = RegExp(r'^bytes=(\d+)-\d*$').firstMatch(requestedRange);
  if (request != null) return int.tryParse(request[1]!) != start;
  return !RegExp(r'^bytes=-[1-9]\d*$').hasMatch(requestedRange);
}

void _validatePrefix(List<int> bytes) {
  final text = utf8
      .decode(bytes.take(512).toList(), allowMalformed: true)
      .replaceFirst('\uFEFF', '')
      .trimLeft()
      .toLowerCase();
  if (text.startsWith('<') ||
      text.startsWith('#!') ||
      text.startsWith('#extm3u') ||
      text.startsWith('[playlist]') ||
      text.startsWith('ffconcat') ||
      (bytes.length >= 2 && bytes[0] == 0x4d && bytes[1] == 0x5a) ||
      (bytes.length >= 4 &&
          bytes[0] == 0x7f &&
          text.substring(1).startsWith('elf'))) {
    throw const FormatException('来源返回非媒体内容或未受控播放列表，已拦截');
  }
}
