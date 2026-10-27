import 'dart:convert';
import 'dart:io';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/header_policy.dart';
import '../../../core/network/media_http_client.dart';
import '../../../media/cache/segment_fetcher.dart';
import '../data/download_repository.dart';
import '../domain/download_task.dart';
import 'download_format.dart';
import 'hls_download.dart';
import 'mp4_download.dart';

Future<void> transferDownload({
  required DownloadTask task,
  required CancellationToken token,
  required DownloadRepository repository,
  required SegmentFetcher fetcher,
  required MediaHttpClient http,
  required int limit,
  required void Function(int) reserve,
  required Future<void> Function(File, CancellationToken) validate,
}) async {
  final headers = Map<String, String>.from(
    jsonDecode(task.row['headers'] as String),
  );
  final policy = HeaderPolicy({task.uri: headers});
  final directory = Directory(task.directory);
  await directory.create(recursive: true);
  String local;
  if (await isMp4Download(task.uri, http, policy, token)) {
    await downloadMp4(
      uri: task.uri,
      directory: directory,
      http: http,
      policy: policy,
      cancellation: token,
      maxBytes: limit,
      reserveBytes: reserve,
      progress: (c, t, b) => repository.progress(task.id, c, t, b),
      validate: validate,
    );
    local = 'video.mp4';
  } else {
    final job = HlsDownload(
      id: task.id,
      directory: directory,
      fetcher: fetcher,
      http: http,
      policy: policy,
      cancellation: token,
      maxBytes: limit,
      reserveBytes: reserve,
      onProgress: (c, t, b) => repository.progress(task.id, c, t, b),
    );
    local = await job.run(task.uri);
    await repository.progress(task.id, job.completed, job.completed, job.bytes);
  }
  token.check();
  await repository.complete(task.id, local);
}
