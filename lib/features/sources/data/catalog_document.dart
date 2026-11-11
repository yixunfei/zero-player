import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../core/network/document_client.dart';

/// Some TVBox publishers wrap data in an image or a self-contained AES envelope.
Future<String> decodeCatalogDocument(Document document) async {
  final raw = latin1.decode(document.bytes).trim();
  final prefix = raw.startsWith('ï»¿') ? raw.substring(3).trimLeft() : raw;
  if (prefix.startsWith('{') ||
      prefix.startsWith('[') ||
      prefix.startsWith('//') ||
      prefix.startsWith('/*') ||
      prefix.startsWith('#EXTM3U')) {
    return document.text;
  }
  final marker = RegExp(r'[A-Za-z0-9]{8}\*\*').firstMatch(raw);
  final text = marker == null
      ? (prefix.startsWith('2423') ? prefix : document.text)
      : utf8.decode(
          base64.decode(
            raw.substring(marker.end).replaceAll(RegExp(r'\s+'), ''),
          ),
        );
  if (!text.trimLeft().startsWith('2423')) return text;
  return _decodeCbc(text);
}

Future<String> _decodeCbc(String input) async {
  final hex = input.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  final endOfKey = hex.indexOf('2324', 4);
  final endOfData = hex.length - 26;
  if (endOfKey <= 4 ||
      endOfKey > 36 ||
      endOfData <= endOfKey + 4 ||
      (endOfData - endOfKey - 4) % 32 != 0 ||
      !RegExp(r'^[0-9a-f]+$').hasMatch(hex)) {
    throw const FormatException('TVBox 配置包装格式无效');
  }
  final key = ascii.decode(_hexBytes(hex.substring(4, endOfKey))).toLowerCase();
  final nonce = ascii.decode(_hexBytes(hex.substring(endOfData))).toLowerCase();
  try {
    final clear = await AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty)
        .decrypt(
          SecretBox(
            _hexBytes(hex.substring(endOfKey + 4, endOfData)),
            nonce: ascii.encode(nonce.padRight(16, '0')),
            mac: Mac.empty,
          ),
          secretKey: SecretKey(ascii.encode(key.padRight(16, '0'))),
        );
    return utf8.decode(clear);
  } on ArgumentError {
    throw const FormatException('TVBox 配置包装无法解码');
  }
}

List<int> _hexBytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];
