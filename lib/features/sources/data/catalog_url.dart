import '../../../core/network/network_target_policy.dart';

Uri parseCatalogUrl(String input) {
  final value = input.trim().replaceFirstMapped(
    RegExp(r'^(https?):/(?!/)', caseSensitive: false),
    (match) => '${match[1]}://',
  );
  final uri = Uri.parse(value);
  NetworkTargetPolicy.validateUri(uri);
  final host = Uri.decodeComponent(uri.host).replaceAll(RegExp('[。．｡]'), '.');
  if (host == uri.host) return uri;
  final ascii = host
      .toLowerCase()
      .split('.')
      .map(
        (label) => label.codeUnits.any((unit) => unit >= 128)
            ? _encodeDomainLabel(label)
            : label,
      )
      .join('.');
  return uri.replace(host: ascii);
}

Uri? resolveCatalogUrl(Object? value, Uri origin) {
  if (value is! String || value.trim().isEmpty) return null;
  try {
    final reference = value.trim();
    if (reference.startsWith('csp_')) return null;
    return parseCatalogUrl(
      RegExp(r'^https?:/', caseSensitive: false).hasMatch(reference)
          ? reference
          : origin.resolve(reference).toString(),
    );
  } on FormatException {
    return null;
  }
}

String _encodeDomainLabel(String label) {
  // RFC 3492 Bootstring parameters for Punycode.
  final points = label.runes.toList();
  if (points.length > 63 ||
      !RegExp(r'^[\p{L}\p{N}\p{M}-]+$', unicode: true).hasMatch(label)) {
    throw const FormatException('域名标签无效');
  }
  final basic = points.where((point) => point < 128).toList();
  final output = StringBuffer('xn--')..write(String.fromCharCodes(basic));
  if (basic.isNotEmpty) output.write('-');
  var handled = basic.length;
  var nextCodePoint = 128;
  var delta = 0;
  var bias = 72;
  while (handled < points.length) {
    final next = points
        .where((point) => point >= nextCodePoint)
        .reduce((a, b) => a < b ? a : b);
    delta += (next - nextCodePoint) * (handled + 1);
    nextCodePoint = next;
    for (final point in points) {
      if (point < nextCodePoint) delta++;
      if (point != nextCodePoint) continue;
      var digit = delta;
      for (var k = 36; ; k += 36) {
        final threshold = (k - bias).clamp(1, 26);
        if (digit < threshold) break;
        output.writeCharCode(
          _digit(threshold + (digit - threshold) % (36 - threshold)),
        );
        digit = (digit - threshold) ~/ (36 - threshold);
      }
      output.writeCharCode(_digit(digit));
      bias = _adapt(delta, handled + 1, handled == basic.length);
      delta = 0;
      handled++;
    }
    delta++;
    nextCodePoint++;
  }
  if (output.length > 63) throw const FormatException('域名标签太长');
  return output.toString();
}

int _digit(int value) => value < 26 ? 97 + value : 22 + value;

int _adapt(int delta, int points, bool first) {
  var value = first ? delta ~/ 700 : delta ~/ 2;
  value += value ~/ points;
  var offset = 0;
  while (value > 455) {
    value ~/= 35;
    offset += 36;
  }
  return offset + 36 * value ~/ (value + 38);
}
