import 'dart:io';

/// Browser metadata is not authentication. Capability tokens remain required
/// by media/open routes; this policy adds DNS-rebinding and browser isolation.
bool isNativeLoopbackRequest(
  HttpRequest request,
  int port, {
  bool allowQuery = false,
}) {
  final hosts = request.headers[HttpHeaders.hostHeader];
  return hosts != null &&
      hosts.length == 1 &&
      hosts.single == '127.0.0.1:$port' &&
      !request.uri.hasAuthority &&
      !request.uri.hasScheme &&
      !request.uri.hasFragment &&
      (allowQuery || !request.uri.hasQuery) &&
      ![
        'origin',
        'referer',
        'sec-fetch-site',
        'sec-fetch-mode',
        'sec-fetch-dest',
        'sec-fetch-user',
      ].any((name) => request.headers[name] != null);
}

void secureLoopbackResponse(HttpResponse response) {
  response.headers.set('X-Content-Type-Options', 'nosniff');
  response.headers.set('Cache-Control', 'no-store');
  response.headers.set(
    'Content-Security-Policy',
    "default-src 'none'; sandbox",
  );
  response.headers.set('Cross-Origin-Resource-Policy', 'same-origin');
  response.headers.set('Referrer-Policy', 'no-referrer');
  response.headers.set('X-Frame-Options', 'DENY');
}
