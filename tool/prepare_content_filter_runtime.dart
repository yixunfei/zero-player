import 'dart:io';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/media/content_filter/local_runtime.dart';

/// Explicit developer installation, outside the application bundle.
Future<void> main(List<String> arguments) async {
  final http = MediaHttpClient();
  final directory = Directory(
    arguments.firstOrNull ?? '.tools/content-filter/runtime',
  );
  try {
    final runtime = LocalRuntime(directory, http);
    stdout.writeln(
      'Installing optional runtime into ${directory.absolute.path}',
    );
    await runtime.download(CancellationToken());
    stdout.writeln('Pinned archive and extracted binaries verified.');
  } finally {
    http.close();
  }
}
