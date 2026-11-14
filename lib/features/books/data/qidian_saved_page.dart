import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html;

import '../../../core/network/document_encoding.dart';

const maxQidianSavedPageBytes = 16 * 1024 * 1024;
const _maxHtmlBytes = 2 * 1024 * 1024;
const _invalidPage = FormatException('请选择浏览器保存的起点网页（HTML 或 MHTML）');

typedef QidianSavedPage = ({Uri uri, String text});

QidianSavedPage readQidianSavedPage(List<int> bytes) {
  if (bytes.isEmpty) throw _invalidPage;
  if (bytes.length > maxQidianSavedPageBytes) {
    throw const FormatException('网页文件超过 16 MiB');
  }
  final hasBom =
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
  final prefix = latin1.decode(bytes.skip(hasBom ? 3 : 0).take(4096).toList());
  final marker = RegExp(
    r'<!--\s*saved from url=\(\d+\)(\S+)\s*-->',
  ).firstMatch(prefix);
  if (marker != null) {
    return _savedPage(marker[1], bytes);
  }
  if (prefix.trimLeft().startsWith('<')) return _readHtml(bytes);
  return _readArchive(latin1.decode(bytes).replaceAll('\r\n', '\n'));
}

QidianSavedPage _readHtml(List<int> bytes) {
  final text = _decodeHtml(bytes);
  final head = html.parse(text).head;
  final address =
      head?.querySelector('link[rel="canonical"]')?.attributes['href'] ??
      head
          ?.querySelector('meta[property="og:novel:book_url"]')
          ?.attributes['content'] ??
      head?.querySelector('meta[property="og:url"]')?.attributes['content'];
  return (uri: _savedUri(address), text: text);
}

QidianSavedPage _readArchive(String archive) {
  final top = _headerBlock(archive, 0);
  final type = top.fields['content-type'] ?? '';
  if (!type.toLowerCase().startsWith('multipart/related')) throw _invalidPage;
  final boundary = RegExp(
    r'\bboundary\s*=\s*(?:"([^"]+)"|([^;\s]+))',
    caseSensitive: false,
  ).firstMatch(type);
  final value = boundary?[1] ?? boundary?[2];
  if (value == null || value.length > 70) throw _invalidPage;
  final separator = '\n--$value';
  final start = archive.indexOf('$separator\n', top.end - 1);
  if (start < 0) throw _invalidPage;
  final part = _headerBlock(archive, start + separator.length + 1);
  final htmlType = part.fields['content-type'];
  final location = part.fields['content-location'];
  final snapshot = top.fields['snapshot-content-location'];
  if (htmlType == null ||
      htmlType.split(';').first.trim().toLowerCase() != 'text/html' ||
      location == null ||
      (snapshot != null &&
          Uri.tryParse(snapshot)?.removeFragment() !=
              Uri.tryParse(location)?.removeFragment())) {
    throw _invalidPage;
  }
  final end = archive.indexOf(separator, part.end);
  if (end < 0 || end - part.end > _maxHtmlBytes * 4) throw _invalidPage;
  final encoded = archive.substring(part.end, end);
  final bytes = switch (part.fields['content-transfer-encoding']
      ?.toLowerCase()) {
    'quoted-printable' => _quotedPrintable(encoded),
    'base64' => base64.decode(encoded.replaceAll(RegExp(r'\s'), '')),
    null || '7bit' || '8bit' || 'binary' => latin1.encode(encoded),
    _ => throw _invalidPage,
  };
  return _savedPage(location, bytes, contentType: htmlType);
}

({Map<String, String> fields, int end}) _headerBlock(String text, int start) {
  final end = text.indexOf('\n\n', start);
  if (end < 0 || end - start > 16 * 1024) throw _invalidPage;
  final headers = text
      .substring(start, end)
      .replaceAll(RegExp(r'\n[ \t]+'), ' ');
  final fields = <String, String>{};
  for (final line in headers.split('\n')) {
    final colon = line.indexOf(':');
    if (colon > 0) {
      fields[line.substring(0, colon).toLowerCase()] = line
          .substring(colon + 1)
          .trim();
    }
  }
  return (fields: fields, end: end + 2);
}

List<int> _quotedPrintable(String text) {
  final bytes = BytesBuilder(copy: false);
  for (var i = 0; i < text.length; i++) {
    final byte = text.codeUnitAt(i);
    if (byte != 0x3d) {
      bytes.addByte(byte);
    } else if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0a) {
      i++;
    } else {
      if (i + 2 >= text.length) throw _invalidPage;
      final decoded = int.tryParse(text.substring(i + 1, i + 3), radix: 16);
      if (decoded == null || decoded < 0 || decoded > 255) throw _invalidPage;
      bytes.addByte(decoded);
      i += 2;
    }
  }
  return bytes.takeBytes();
}

QidianSavedPage _savedPage(
  String? location,
  List<int> bytes, {
  String? contentType,
}) => (
  uri: _savedUri(location),
  text: _decodeHtml(bytes, contentType: contentType),
);

Uri _savedUri(String? location) {
  final uri = Uri.tryParse(location ?? '');
  if (uri == null || !uri.hasAuthority) throw _invalidPage;
  return uri;
}

String _decodeHtml(List<int> bytes, {String? contentType}) {
  if (bytes.length > _maxHtmlBytes) {
    throw const FormatException('网页正文超过 2 MiB');
  }
  return decodeDocumentText(bytes, contentType: contentType);
}
