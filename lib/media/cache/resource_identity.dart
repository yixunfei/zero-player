import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Never normalizes away tokens or drops headers/ranges that affect content.
String resourceIdentity(Uri uri, Map<String, String> headers, String? range) {
  final normalized = <String, String>{
    for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
  };
  final keys = normalized.keys.toList()..sort();
  return sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'uri': uri.toString(),
            'headers': {for (final key in keys) key: normalized[key]},
            'range': range,
          }),
        ),
      )
      .toString();
}
