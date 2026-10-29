import 'dart:io';

import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/media/content_filter/local_models.dart';

/// Fetches the same pinned, verified assets used by the application.
Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    stderr.writeln(
      'Usage: dart run tool/prepare_content_filter_models.dart [directory]',
    );
    exitCode = 64;
    return;
  }
  final directory = Directory(
    arguments.firstOrNull ?? '.tools/content-filter/models',
  );
  final http = MediaHttpClient();
  try {
    stdout.writeln(
      'Preparing ${LocalModels.totalBytes} bytes in ${directory.absolute.path}',
    );
    await LocalModels(directory, http).download(CancellationToken());
    stdout.writeln(
      'All four model assets passed size and SHA256 verification.',
    );
  } finally {
    http.close();
  }
}
