import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import '../../core/network/cancellation_token.dart';
import '../../core/network/media_http_client.dart';
import 'filter_types.dart';
import 'resource_download.dart';
import 'runtime_catalog.dart';

/// Only pinned, integrity-checked upstream CPU binaries can be installed.
final class LocalRuntime {
  LocalRuntime(this.directory, this.http, {RuntimePackage? package})
    : package = package ?? RuntimePackage.current();
  final Directory directory;
  final MediaHttpClient http;
  final RuntimePackage package;
  bool _verified = false;

  Future<bool> installed() async {
    for (final asset in package.files) {
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
    for (final asset in package.files) {
      token.check();
      if (!await validResource(
        File('${directory.path}/${asset.name}'),
        asset,
      )) {
        throw const FilterFailure('增强运行库未安装或损坏，请在设置中手动下载');
      }
    }
    _verified = true;
  }

  Future<void> download(
    CancellationToken token, {
    ResourceProgress? progress,
  }) async {
    try {
      await ensure(token);
      return;
    } on FilterFailure {
      /* Install explicitly. */
    }
    await directory.create(recursive: true);
    final archive = File('${directory.path}/runtime.tar.gz');
    try {
      await downloadResource(
        http,
        archive,
        package.archive,
        token,
        progress: progress,
      );
      token.check();
      final path = archive.path, target = directory.path, catalog = package;
      await Isolate.run(() => extractRuntime(path, target, catalog));
      token.check();
      await ensure(token);
    } finally {
      if (await archive.exists()) await archive.delete();
    }
  }

  Future<void> remove() async {
    _verified = false;
    for (final asset in package.files) {
      final file = File('${directory.path}/${asset.name}');
      if (await file.exists()) await file.delete();
    }
  }
}

Future<void> extractRuntime(
  String archivePath,
  String target,
  RuntimePackage package,
) async {
  // Validate again in the worker before parsing any archive data.
  final archiveFile = File(archivePath);
  if (!await validResource(archiveFile, package.archive)) {
    throw const FilterFailure('运行库压缩包校验失败');
  }
  final bytes = await archiveFile.readAsBytes();
  final archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  for (final asset in package.files) {
    final member = archive.findFile('${package.prefix}${asset.name}');
    if (member == null ||
        !member.isFile ||
        member.isSymbolicLink ||
        member.size != asset.bytes) {
      throw const FilterFailure('运行库文件清单不匹配');
    }
    // Paths are compiled-in basenames, never names supplied by the archive.
    final temporary = File('$target/${asset.name}.part');
    try {
      await temporary.writeAsBytes(member.content, flush: true);
      if (!await validResource(temporary, asset)) {
        throw const FilterFailure('运行库二进制校验失败');
      }
      final file = File('$target/${asset.name}');
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
