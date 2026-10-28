import 'dart:async';
import 'dart:io';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../core/network/request_scheduler.dart';

final class SourceConnection {
  const SourceConnection({
    this.addresses = const [],
    this.dnsMs,
    this.tcpMs,
    this.missingDomain = false,
    this.evidence = const [],
  });
  final List<String> addresses, evidence;
  final int? dnsMs, tcpMs;
  final bool missingDomain;
}

abstract interface class SourceConnectivity {
  Future<SourceConnection> inspect(Uri uri, CancellationToken token);
}

final class NetworkSourceConnectivity implements SourceConnectivity {
  const NetworkSourceConnectivity(
    this.network, {
    this.lookup = InternetAddress.lookup,
    this.resolvers = const [
      'https://dns.google/resolve',
      'https://cloudflare-dns.com/dns-query',
    ],
  });
  final DocumentClient network;
  final Future<List<InternetAddress>> Function(String) lookup;
  final List<String> resolvers;

  @override
  Future<SourceConnection> inspect(Uri uri, CancellationToken token) async {
    final watch = Stopwatch()..start();
    List<InternetAddress> addresses = [];
    try {
      addresses = await lookup(uri.host).timeout(const Duration(seconds: 3));
    } on Exception {
      /* A local DNS failure alone never proves deletion. */
    }
    watch.stop();
    token.check();
    final evidence = <String>[];
    var missing = false;
    if (addresses.isEmpty && _publicHostname(uri.host)) {
      final confirmations = await Future.wait([
        for (final resolver in resolvers.take(2))
          _missingAt(resolver, uri.host, token),
      ]);
      missing =
          confirmations.length == 2 && confirmations.every((result) => result);
      evidence.addAll([
        '本机 DNS 无结果',
        for (var i = 0; i < confirmations.length; i++)
          '${Uri.parse(resolvers[i]).host}: ${confirmations[i] ? 'NXDOMAIN' : '未确认域名不存在'}',
      ]);
    }
    token.check();
    int? tcpMs;
    for (final address in addresses.take(2)) {
      token.check();
      Socket? socket;
      final clock = Stopwatch()..start();
      try {
        network.http.targetPolicy.validateAddress(address);
        socket = await Socket.connect(
          address,
          uri.port,
          timeout: const Duration(seconds: 2),
        );
        tcpMs = clock.elapsedMilliseconds;
      } on Exception {
        /* The HTTP result remains authoritative. */
      } finally {
        socket?.destroy();
      }
      if (tcpMs != null) break;
    }
    token.check();
    return SourceConnection(
      addresses: addresses.map((a) => a.address).toSet().toList(),
      dnsMs: watch.elapsedMilliseconds,
      tcpMs: tcpMs,
      missingDomain: missing,
      evidence: evidence,
    );
  }

  bool _publicHostname(String host) =>
      InternetAddress.tryParse(host) == null &&
      host.contains('.') &&
      ![
        '.local',
        '.localhost',
        '.test',
        '.invalid',
        '.example',
      ].any(host.endsWith);

  Future<bool> _missingAt(
    String resolver,
    String host,
    CancellationToken token,
  ) async {
    try {
      final response = await network.get(
        Uri.parse(
          resolver,
        ).replace(queryParameters: {'name': host, 'type': 'A'}),
        headers: const {'Accept': 'application/dns-json'},
        maxBytes: 65536,
        priority: RequestPriority.background,
        cancellation: token,
        networkTimeout: const Duration(seconds: 5),
      );
      final data = response.json;
      if (data is! Map || data['Status'] != 3) return false;
      final question = data['Question'];
      return question is List &&
          question.any(
            (q) =>
                q is Map &&
                '${q['name']}'.toLowerCase().replaceFirst(RegExp(r'\.$'), '') ==
                    host.toLowerCase(),
          );
    } catch (_) {
      token.check();
      return false;
    }
  }
}
