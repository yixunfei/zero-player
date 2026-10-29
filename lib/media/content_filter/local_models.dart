import 'dart:io';

import 'resource_download.dart';
export 'resource_download.dart' show ModelAsset;

import '../../core/network/cancellation_token.dart';
import '../../core/network/media_http_client.dart';
import 'filter_types.dart';

/// Revisions and digests are pinned; no executable files are downloaded.
final class LocalModels {
  LocalModels(this.directory, this.http);
  final Directory directory;
  final MediaHttpClient http;
  Future<void>? _pending;
  final _verified = <String>{};
  static const _speech =
      'https://huggingface.co/csukuangfj/'
      'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/'
      '2365baeacb507f821a0c8120fcee3d484dba7a07';
  static const _ocr =
      'https://huggingface.co/SWHL/RapidOCR/resolve/'
      '1cfba2e90fc938db55889873735088de210cc173/PP-OCRv4';
  static const assets = [
    ModelAsset(
      'speech.onnx',
      '$_speech/model.int8.onnx',
      239233841,
      'c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51',
    ),
    ModelAsset(
      'tokens.txt',
      '$_speech/tokens.txt',
      315894,
      'f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc',
    ),
    ModelAsset(
      'det.onnx',
      '$_ocr/ch_PP-OCRv4_det_infer.onnx',
      4745517,
      'd2a7720d45a54257208b1e13e36a8479894cb74155a5efe29462512d42f49da9',
    ),
    ModelAsset(
      'rec.onnx',
      '$_ocr/ch_PP-OCRv4_rec_infer.onnx',
      10857958,
      '48fc40f24f6d2a207a2b1091d3437eb3cc3eb6b676dc3ef9c37384005483683b',
    ),
  ];
  static int get totalBytes =>
      assets.fold(0, (sum, model) => sum + model.bytes);

  static Iterable<ModelAsset> selected({bool ocr = true, bool asr = true}) =>
      assets.where(
        (a) => a.name.endsWith('.txt') || a.name == 'speech.onnx' ? asr : ocr,
      );

  Future<bool> installed({bool ocr = true, bool asr = true}) async {
    for (final asset in selected(ocr: ocr, asr: asr)) {
      final file = File('${directory.path}/${asset.name}');
      if (!await file.exists() || await file.length() != asset.bytes) {
        return false;
      }
    }
    return true;
  }

  Future<void> ensure(
    CancellationToken token, {
    bool ocr = true,
    bool asr = true,
  }) async {
    for (final asset in selected(ocr: ocr, asr: asr)) {
      token.check();
      if (_verified.contains(asset.name)) continue;
      if (!await validResource(
        File('${directory.path}/${asset.name}'),
        asset,
      )) {
        throw const FilterFailure('增强识别资源尚未安装，请在设置中手动下载；播放不会自动下载');
      }
      _verified.add(asset.name);
    }
  }

  /// Only the explicit resource-download action may invoke this method.
  Future<void> download(
    CancellationToken token, {
    bool ocr = true,
    bool asr = true,
    ResourceProgress? progress,
  }) async {
    if (_pending != null) throw const FilterFailure('已有资源正在下载');
    final pending = _pending = _install(token, ocr, asr, progress);
    try {
      await pending;
      token.check();
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  Future<void> _install(
    CancellationToken token,
    bool ocr,
    bool asr,
    ResourceProgress? progress,
  ) async {
    await directory.create(recursive: true);
    for (final asset in selected(ocr: ocr, asr: asr)) {
      token.check();
      final file = File('${directory.path}/${asset.name}');
      if (!await validResource(file, asset)) {
        await downloadResource(http, file, asset, token, progress: progress);
      }
      _verified.add(asset.name);
    }
  }

  Future<void> remove({required bool ocr, required bool asr}) async {
    if (_pending != null) throw const FilterFailure('请先取消资源下载');
    for (final asset in selected(ocr: ocr, asr: asr)) {
      _verified.remove(asset.name);
      final file = File('${directory.path}/${asset.name}');
      if (await file.exists()) await file.delete();
    }
  }
}
