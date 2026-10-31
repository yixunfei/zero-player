import 'dart:async';
import 'dart:io';

Map<String, String> diagnosticHttpHeaders(HttpHeaders headers) {
  final values = <String, String>{};
  headers.forEach((name, content) => values[name] = content.join(', '));
  return values;
}

const _traceKey = #zeroPlayerRequestTrace;

Future<T> traceRequests<T>(
  List<Map<String, Object?>> target,
  Future<T> Function() action,
) => runZoned(action, zoneValues: {_traceKey: target});

String safeDiagnosticUrl(Uri uri) => uri
    .removeFragment()
    .replace(
      userInfo: '',
      path: uri.path.isEmpty || uri.path == '/' ? uri.path : '/[已隐藏路径]',
      queryParameters: uri.hasQuery
          ? {
              for (final entry in uri.queryParametersAll.entries)
                entry.key: ['[已隐藏]'],
            }
          : null,
    )
    .toString();

Map<String, String> safeDiagnosticHeaders(Map<String, String> headers) => {
  for (final entry in headers.entries)
    entry.key: {'referer', 'location'}.contains(entry.key.toLowerCase())
        ? safeDiagnosticUrl(Uri.tryParse(entry.value) ?? Uri())
        : {
            'accept',
            'accept-encoding',
            'content-type',
            'content-length',
            'range',
            'content-range',
            'user-agent',
          }.contains(entry.key.toLowerCase())
        ? entry.value.substring(0, entry.value.length.clamp(0, 512))
        : '[已隐藏]',
};

void recordRequestTrace({
  required Uri uri,
  required int elapsedMs,
  required Map<String, String> requestHeaders,
  int? status,
  Map<String, String> responseHeaders = const {},
  String? error,
}) {
  final target = Zone.current[_traceKey] as List<Map<String, Object?>>?;
  if (target == null || target.length >= 16) return;
  target.add({
    'method': 'GET',
    'url': safeDiagnosticUrl(uri),
    'elapsedMs': elapsedMs,
    'status': status,
    'requestHeaders': safeDiagnosticHeaders(requestHeaders),
    'responseHeaders': safeDiagnosticHeaders(responseHeaders),
    'error': error,
  });
}
