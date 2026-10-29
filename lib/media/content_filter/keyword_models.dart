import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import '../../core/network/cancellation_token.dart';
import '../../core/network/media_http_client.dart';
import 'filter_types.dart';
import 'resource_download.dart';

/// Quantized bilingual keyword model; installed only from the resource dialog.
final class KeywordModels {
  KeywordModels(this.directory, this.http);
  final Directory directory;
  final MediaHttpClient http;
  bool _verified = false;
  static const prefix = 'sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20';
  static const archive = ModelAsset(
    'keywords.tar.bz2',
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/$prefix.tar.bz2',
    32885699,
    '68447f4fbc67e70eee3a93961f36e81e98f47aef73ce7e7ca00885c6cd3616a6',
  );
  static const assets = [
    ModelAsset(
      'encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx',
      '',
      4599656,
      '408bbd740838c42d5bf6d1c5b80b3c88b616c7860b92d980328b5b068c76ae48',
    ),
    ModelAsset(
      'decoder-epoch-13-avg-2-chunk-16-left-64.onnx',
      '',
      759829,
      '63a22dd60f40fff082ac3e09afa507f6787da36df76ded2fbe145fa233e22c21',
    ),
    ModelAsset(
      'joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx',
      '',
      86629,
      '190d4067b4cc20b72a42a1916e69d92052000fb7051a427ebb1bc72a69207dc1',
    ),
    ModelAsset(
      'tokens.txt',
      '',
      1928,
      '2d3f32311f9b692b964da3c90e830258d3e78e013cb0c992dbfb15cd5a1a71b0',
    ),
  ];
  static int get totalBytes =>
      assets.fold(0, (sum, asset) => sum + asset.bytes);

  Future<bool> installed() async {
    for (final asset in assets) {
      final file = File('${directory.path}/${asset.name}');
      if (!await file.exists() || await file.length() != asset.bytes) {
        return false;
      }
    }
    return true;
  }

  Future<void> ensure(CancellationToken token) async {
    token.check();
    if (_verified) return;
    for (final asset in assets) {
      token.check();
      if (!await validResource(
        File('${directory.path}/${asset.name}'),
        asset,
      )) {
        throw const FilterFailure('常见词语音资源未安装，请在设置中手动下载');
      }
    }
    _verified = true;
  }

  Future<void> download(
    CancellationToken token, {
    ResourceProgress? progress,
  }) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/${archive.name}');
    try {
      await downloadResource(http, file, archive, token, progress: progress);
      token.check();
      final path = file.path, target = directory.path;
      await Isolate.run(() => _extractKeywords(path, target));
      token.check();
      await ensure(token);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> remove() async {
    _verified = false;
    for (final asset in assets) {
      final file = File('${directory.path}/${asset.name}');
      if (await file.exists()) await file.delete();
    }
  }
}

Future<void> _extractKeywords(String path, String target) async {
  final file = File(path);
  if (!await validResource(file, KeywordModels.archive)) {
    throw const FilterFailure('关键词资源归档校验失败');
  }
  final archive = TarDecoder().decodeBytes(
    BZip2Decoder().decodeBytes(await file.readAsBytes()),
  );
  for (final asset in KeywordModels.assets) {
    final member = archive.findFile('${KeywordModels.prefix}/${asset.name}');
    if (member == null ||
        !member.isFile ||
        member.isSymbolicLink ||
        member.size != asset.bytes) {
      throw const FilterFailure('关键词资源清单不匹配');
    }
    final temporary = File('$target/${asset.name}.part');
    try {
      await temporary.writeAsBytes(member.content, flush: true);
      if (!await validResource(temporary, asset)) {
        throw const FilterFailure('关键词模型校验失败');
      }
      final destination = File('$target/${asset.name}');
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
