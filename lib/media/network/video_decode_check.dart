import 'dart:async';
import 'dart:io';

import '../../core/network/cancellation_token.dart';
import '../../core/network/header_policy.dart';
import '../content_filter/native_media_commands.dart';
import '../gateway/media_gateway.dart';

/// Confirms that a guarded input can decode a continuous video sample.
final class VideoDecodeCheck {
  VideoDecodeCheck(this.gateway, {NativeMediaCommands? commands})
    : commands = commands ?? NativeMediaCommands();

  final MediaGateway gateway;
  final NativeMediaCommands commands;

  Future<bool> sample(
    Uri uri,
    Map<String, String> headers,
    CancellationToken caller,
  ) async {
    await gateway.start();
    caller.check();
    final token = CancellationToken();
    final session = gateway.createSession(HeaderPolicy({uri: headers}))
      ..cacheEnabled = false;
    final stopSession = token.listen(session.close);
    final stopCaller = caller.listen(token.cancel);
    final deadline = Timer(const Duration(seconds: 30), token.cancel);
    Directory? scratch;
    File? output;
    try {
      final input = await session.openMedia(uri);
      token.check();
      final playlist = gateway.isRegisteredPlaylist(input);
      scratch = await Directory.systemTemp.createTemp('zero-video-check-');
      output = File('${scratch.path}${Platform.pathSeparator}frames.raw');
      await commands.run(
        [
          '-xerror',
          '-protocol_whitelist',
          'http,tcp,crypto',
          '-format_whitelist',
          playlist ? 'hls,mpegts,mov,flv' : 'mpegts,mov,flv',
          if (playlist) ...['-f', 'hls', ...NativeMediaCommands.hlsOptions],
          '-threads',
          '2',
          '-i',
          input.toString(),
          '-map',
          '0:v:0',
          '-t',
          '20',
          '-vf',
          'fps=2,scale=32:32',
          '-an',
          '-threads',
          '1',
          '-pix_fmt',
          'gray',
          '-f',
          'rawvideo',
          output.path,
        ],
        token,
        timeout: const Duration(seconds: 30),
      );
      token.check();
      return await output.length() >= 39 * 32 * 32;
    } catch (_) {
      caller.check();
      return false;
    } finally {
      deadline.cancel();
      stopCaller();
      stopSession();
      session.close();
      try {
        if (output != null && await output.exists()) await output.delete();
        if (scratch != null) await scratch.delete();
      } on FileSystemException {
        // A native session can briefly retain its output file during teardown.
      }
    }
  }
}
