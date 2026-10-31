import 'dart:io';

/// LAN permissions deliberately exclude local services and metadata endpoints.
bool isLanAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (bytes.length == 4) {
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }
  return bytes[0] & 0xfe == 0xfc;
}
