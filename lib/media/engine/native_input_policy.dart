import '../../core/network/network_target_policy.dart';

/// Native demuxers only receive live capability URLs issued by this process.
void validateNativeInput(Uri uri, {required bool registered}) {
  NetworkTargetPolicy.validateUri(uri);
  if (!registered ||
      uri.scheme != 'http' ||
      uri.host != '127.0.0.1' ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('播放器仅接受已登记的受控媒体资源');
  }
}
