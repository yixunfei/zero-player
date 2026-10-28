import 'dart:io';

/// External source data cannot reach local services, credentials or file URLs.
/// Tests must explicitly opt in to private fixture servers.
final class NetworkTargetPolicy {
  const NetworkTargetPolicy({this.allowPrivateNetworks = false});
  final bool allowPrivateNetworks;

  static void validateUri(Uri uri) {
    if (!{'http', 'https'}.contains(uri.scheme) ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port < 1 ||
        uri.port > 65535 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(Uri.decodeFull(uri.toString()))) {
      throw const FormatException('仅允许不含凭据的 HTTP(S) 媒体地址');
    }
  }

  void validateAddress(InternetAddress address) {
    if (!allowPrivateNetworks && isPrivate(address)) {
      throw const FormatException('已拦截来源对本机或私有网络的访问');
    }
  }

  static bool isPrivate(InternetAddress address) {
    final bytes = address.rawAddress;
    if (bytes.length == 4) {
      return bytes[0] == 0 ||
          bytes[0] == 10 ||
          bytes[0] == 127 ||
          (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) ||
          (bytes[0] == 169 && bytes[1] == 254) ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && (bytes[1] == 168 || bytes[1] == 0)) ||
          (bytes[0] == 198 && (bytes[1] == 18 || bytes[1] == 19)) ||
          bytes[0] >= 224;
    }
    if (bytes.take(10).every((v) => v == 0) &&
        bytes[10] == 255 &&
        bytes[11] == 255) {
      return isPrivate(InternetAddress.fromRawAddress(bytes.sublist(12)));
    }
    // Permit only global unicast; excludes loopback, link-local, ULA, multicast
    // and IPv4-compatible/tunnel addresses that could conceal local targets.
    return bytes[0] & 0xe0 != 0x20 ||
        (bytes[0] == 0x20 && bytes[1] == 0x02) ||
        (bytes[0] == 0x20 &&
            bytes[1] == 0x01 &&
            bytes[2] == 0 &&
            bytes[3] == 0);
  }

  Future<ConnectionTask<Socket>> connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    validateUri(uri);
    if (proxyHost != null) throw const FormatException('不支持未校验的代理目标');
    final addresses = await InternetAddress.lookup(
      uri.host,
    ).timeout(const Duration(seconds: 5));
    if (addresses.isEmpty) {
      throw const SocketException('DNS returned no address');
    }
    for (final address in addresses) {
      validateAddress(address);
    }
    // Connect to the checked address, never resolve the host a second time.
    final address =
        addresses
            .where((a) => a.type == InternetAddressType.IPv4)
            .firstOrNull ??
        addresses.first;
    final task = await Socket.startConnect(address, uri.port);
    if (uri.scheme != 'https') return task;
    Socket? connected;
    final secure = task.socket.then((socket) {
      connected = socket;
      // A custom connectionFactory owns TLS as well as TCP. Keep SNI and
      // certificate verification bound to the original hostname.
      return SecureSocket.secure(socket, host: uri.host);
    });
    return ConnectionTask.fromSocket(secure, () {
      task.cancel();
      connected?.destroy();
    });
  }
}
