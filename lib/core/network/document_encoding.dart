import 'dart:convert';
import 'package:enough_convert/gbk.dart';

String decodeDocumentText(List<int> bytes, {String? contentType}) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    return utf8.decode(bytes.sublist(3));
  }
  final charset = _charset(contentType ?? '') ?? _htmlCharset(bytes);
  switch (charset?.toLowerCase().replaceAll('_', '-')) {
    case 'utf8':
    case 'utf-8':
      return utf8.decode(bytes);
    case 'gbk':
    case 'gb2312':
    case 'gb-2312':
    case 'cp936':
      return gbk.decode(bytes);
    case 'gb18030':
      if (_hasFourByteCharacter(bytes)) {
        throw const FormatException('来源使用 GB18030 四字节字符，当前仅支持其 GBK 兼容部分');
      }
      return gbk.decode(bytes);
    case 'ascii':
    case 'us-ascii':
      return ascii.decode(bytes);
    case 'iso-8859-1':
    case 'latin1':
      return latin1.decode(bytes);
    case null:
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return gbk.decode(bytes);
      }
    default:
      throw FormatException('来源使用未支持的字符集：$charset');
  }
}

String? _charset(String value) => RegExp(
  r'''charset\s*=\s*["']?\s*([a-zA-Z0-9_-]+)''',
  caseSensitive: false,
).firstMatch(value)?[1];

String? _htmlCharset(List<int> bytes) {
  final prefix = latin1.decode(bytes.take(4096).toList());
  for (final match in RegExp(
    r'<meta\b[^>]*>',
    caseSensitive: false,
  ).allMatches(prefix)) {
    final charset = _charset(match[0]!);
    if (charset != null) return charset;
  }
  return null;
}

bool _hasFourByteCharacter(List<int> bytes) {
  for (var i = 0; i + 3 < bytes.length; i++) {
    if (bytes[i] >= 0x81 &&
        bytes[i] <= 0xfe &&
        bytes[i + 1] >= 0x30 &&
        bytes[i + 1] <= 0x39 &&
        bytes[i + 2] >= 0x81 &&
        bytes[i + 2] <= 0xfe &&
        bytes[i + 3] >= 0x30 &&
        bytes[i + 3] <= 0x39) {
      return true;
    }
  }
  return false;
}
