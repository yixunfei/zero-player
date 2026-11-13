import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'legado_script_stub.dart'
    if (dart.library.ui) 'legado_script_flutter.dart'
    as engine;

final class LegadoNeedsDocument implements Exception {
  const LegadoNeedsDocument(this.address);
  final String address;
}

const _bridge = r'''
var __zpLegadoRequests;
const java = (() => {
  const known = __zpLegadoKnown;
  const pending = [];
  __zpLegadoRequests = () => pending;
  const request = (method, ...args) => {
    const key = JSON.stringify([method, ...args]);
    if (Object.prototype.hasOwnProperty.call(known, key)) return known[key];
    if (pending.length < 8) pending.push([method, ...args]);
    throw new Error('Rule data pending');
  };
  const store = Object.create(null);
  return Object.freeze({
    ajax: url => request('ajax', String(url)),
    getString: (rule, input = result) => request('string', String(rule), input),
    getStringList: (rule, input = result) => request('list', String(rule), input),
    getElements: (rule, input = result) => request('elements', String(rule), input),
    encodeURI: text => encodeURIComponent(String(text)),
    base64Encode: value => request('base64Encode', String(value)),
    base64Decode: value => request('base64Decode', String(value)),
    hexDecodeToString: value => request('hexDecode', String(value)),
    md5Encode: value => request('md5', String(value)),
    put: (key, value) => (store[key] = value),
    get: key => store[key] ?? '',
    log: () => {},
  });
})();
const cache = Object.freeze({get: java.get, put: java.put});
source.getVariable = () => java.get('source.variable');
source.setVariable = value => java.put('source.variable', value);
source.getKey = () => source.bookSourceUrl;
''';

Object? runLegadoScript(
  String script, {
  required String library,
  required Map<String, Object?> context,
  required Map<String, String> documents,
  required Object? Function(String method, String rule, Object? input) select,
}) {
  final known = <String, Object?>{};
  var size = 0;
  final variables = context.entries
      .map((item) => 'var ${item.key} = ${jsonEncode(item.value)};')
      .join('\n');
  for (var round = 0; round < 12; round++) {
    final setup =
        'const __zpLegadoKnown = ${jsonEncode(known)};\n$variables\n$_bridge';
    final evaluation = engine.evaluateLegadoScript(setup, '$library\n$script');
    if (evaluation.requests.isEmpty) {
      if (evaluation.failed) {
        throw const FormatException('Legado 脚本接口不兼容或超过执行限制');
      }
      return evaluation.value;
    }
    var progressed = false;
    for (final request in evaluation.requests.whereType<List>().take(8)) {
      if (request.length < 2 ||
          request[0] is! String ||
          request[1] is! String) {
        continue;
      }
      final id = jsonEncode(request);
      if (known.containsKey(id) || id.length > 3 * 1024 * 1024) continue;
      final method = request[0] as String;
      final value = request[1] as String;
      final result = _result(method, value, request, documents, select);
      size += id.length + jsonEncode(result).length;
      if (size > 8 * 1024 * 1024) {
        throw const FormatException('Legado 脚本辅助数据超过限制');
      }
      known[id] = result;
      progressed = true;
    }
    if (!progressed) break;
  }
  throw const FormatException('Legado 脚本辅助调用超过限制');
}

Object? _result(
  String method,
  String value,
  List request,
  Map<String, String> documents,
  Object? Function(String, String, Object?) select,
) {
  return switch (method) {
    'ajax' => documents[value] ?? (throw LegadoNeedsDocument(value)),
    'string' ||
    'list' ||
    'elements' when request.length == 3 => select(method, value, request[2]),
    'base64Encode' => base64Encode(utf8.encode(value)),
    'base64Decode' => utf8.decode(base64.decode(value), allowMalformed: true),
    'hexDecode' => _hex(value),
    'md5' => md5.convert(utf8.encode(value)).toString(),
    _ => throw const FormatException('Legado 脚本辅助接口无效'),
  };
}

String _hex(String input) {
  if (input.length.isOdd) throw const FormatException('Legado 脚本的十六进制数据无效');
  return utf8.decode([
    for (var i = 0; i < input.length; i += 2)
      int.parse(input.substring(i, i + 2), radix: 16),
  ], allowMalformed: true);
}
