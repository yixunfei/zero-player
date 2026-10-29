import 'dart:io';
import '../../core/network/cancellation_token.dart';
import '../../core/network/media_http_client.dart';
import 'filter_types.dart';
import 'local_models.dart';
import 'local_runtime.dart';
import 'keyword_models.dart';
import 'resource_download.dart';

enum Enhancement { keywords, ocr, asr }

final class OptionalResources {
  OptionalResources(
    Directory root,
    MediaHttpClient http, {
    LocalRuntime? runtime,
  }) : models = LocalModels(Directory('${root.path}/models'), http),
       keywords = KeywordModels(Directory('${root.path}/keywords'), http),
       runtime =
           runtime ?? LocalRuntime(Directory('${root.path}/runtime'), http);
  final LocalModels models;
  final KeywordModels keywords;
  final LocalRuntime runtime;
  int users = 0;
  bool busy = false;

  Future<bool> installed(Enhancement kind) async =>
      await runtime.installed() &&
      (kind == Enhancement.keywords
          ? await keywords.installed()
          : await models.installed(
              ocr: kind == Enhancement.ocr,
              asr: kind == Enhancement.asr,
            ));

  Future<void> download(
    Enhancement kind,
    CancellationToken token, {
    ResourceProgress? progress,
  }) async {
    if (busy || users > 0) throw const FilterFailure('请先退出正在使用增强识别的播放');
    busy = true;
    try {
      await runtime.download(token, progress: progress);
      if (kind == Enhancement.keywords) {
        await keywords.download(token, progress: progress);
      } else {
        await models.download(
          token,
          ocr: kind == Enhancement.ocr,
          asr: kind == Enhancement.asr,
          progress: progress,
        );
      }
    } finally {
      busy = false;
    }
  }

  Future<String> remove(Enhancement kind) async {
    if (busy || users > 0) throw const FilterFailure('请先退出增强识别播放或取消下载');
    busy = true;
    try {
      if (kind == Enhancement.keywords) {
        await keywords.remove();
      } else {
        await models.remove(
          ocr: kind == Enhancement.ocr,
          asr: kind == Enhancement.asr,
        );
      }
      if (!await models.installed(ocr: true, asr: false) &&
          !await models.installed(ocr: false, asr: true) &&
          !await keywords.installed()) {
        try {
          await runtime.remove();
        } on FileSystemException {
          return '模型已删除；共享运行库仍被占用，重启后可再次清理';
        }
      }
      return '资源已删除';
    } finally {
      busy = false;
    }
  }
}
