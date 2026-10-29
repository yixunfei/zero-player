import 'dart:io';
import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/media/content_filter/keyword_models.dart';

/// Exercises the same verified download/extraction used by the resource dialog.
Future<void> main(List<String> args) async {
  final directory = Directory(
    args.isEmpty ? '.tools/content-filter/installed-keywords' : args.single,
  );
  final http = MediaHttpClient();
  final models = KeywordModels(directory, http);
  final token = CancellationToken();
  try {
    await models.download(token);
    await models.ensure(token);
    if (!await models.installed()) throw StateError('Installation incomplete');
    final files = await directory.list().toList();
    if (files.length != KeywordModels.assets.length) {
      throw StateError('Unexpected installer files');
    }
    stdout.writeln(
      'Verified ${files.length} keyword assets, ${KeywordModels.totalBytes} bytes',
    );
  } finally {
    http.close();
  }
}
