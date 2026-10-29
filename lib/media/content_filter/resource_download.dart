import 'dart:io';
import 'package:crypto/crypto.dart';
import '../../core/network/cancellation_token.dart';
import '../../core/network/header_policy.dart';
import '../../core/network/media_http_client.dart';
import 'filter_types.dart';

final class ModelAsset {
  const ModelAsset(this.name, this.url, this.bytes, this.digest);
  final String name;
  final String url;
  final int bytes;
  final String digest;
}

typedef ResourceProgress = void Function(String name, int received, int total);

Future<bool> validResource(File file, ModelAsset asset) async =>
    await file.exists() &&
    await file.length() == asset.bytes &&
    (await sha256.bind(file.openRead()).first).toString() == asset.digest;

Future<void> downloadResource(
  MediaHttpClient http,
  File file,
  ModelAsset asset,
  CancellationToken token, {
  ResourceProgress? progress,
}) async {
  final temporary = File('${file.path}.part');
  IOSink? sink;
  try {
    final payload = await http.open(
      Uri.parse(asset.url),
      policy: HeaderPolicy({}),
      cancellation: token,
    );
    if (payload.response.statusCode != 200) {
      await payload.body.take(0).drain<void>();
      throw const FilterFailure('增强资源下载失败，请稍后重试');
    }
    sink = temporary.openWrite();
    var count = 0;
    await for (final chunk in payload.body) {
      token.check();
      count += chunk.length;
      if (count > asset.bytes) throw const FilterFailure('资源长度校验失败');
      sink.add(chunk);
      progress?.call(asset.name, count, asset.bytes);
    }
    await sink.close();
    sink = null;
    token.check();
    if (!await validResource(temporary, asset)) {
      throw const FilterFailure('资源完整性校验失败');
    }
    token.check();
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  } finally {
    await sink?.close();
    if (await temporary.exists()) await temporary.delete();
  }
}
