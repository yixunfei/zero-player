import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/network/header_policy.dart';
import '../../../media/cache/segment_store.dart';
import '../../../media/engine/media_kit_engine.dart';
import '../../../media/gateway/media_gateway.dart';

/// M0 diagnostic workflow, kept separate from the eventual playback session.
final class LabController extends ChangeNotifier {
  LabController({this.allowPrivateNetworks = false}) {
    _subscriptions.add(
      engine.errors.listen((_) {
        status = '播放失败，请检查地址或重试';
        notifyListeners();
      }),
    );
  }

  late final engine = MediaKitEngine(
    isTrustedPlaylist: (uri) => gateway?.isRegisteredPlaylist(uri) == true,
  );
  final bool allowPrivateNetworks;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  MediaGateway? gateway;
  GatewaySession? _session;
  String status = '输入媒体地址，或播放本地测试样本';
  bool opening = false;
  bool useGateway = true;
  bool television = false;
  bool dark = true;
  int _generation = 0;
  Directory? _cacheDirectory;

  Future<void> initialize() async {
    final temporary = await getTemporaryDirectory();
    final root = await Directory(
      p.join(temporary.path, 'zero-player-lab'),
    ).create(recursive: true);
    _cacheDirectory = await root.createTemp('session-');
    gateway = MediaGateway(
      SegmentStore(_cacheDirectory!),
      allowPrivateNetworks: allowPrivateNetworks,
    );
    await gateway!.start();
  }

  Future<void> open(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      status = '请输入有效的 HTTP 或 HTTPS 媒体地址';
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    opening = true;
    status = '正在打开媒体…';
    notifyListeners();
    try {
      _session?.close();
      _session = gateway!.createSession(HeaderPolicy({}))
        ..cacheEnabled = useGateway;
      final target = await _session!.openMedia(uri);
      await engine.open(target);
      if (generation != _generation) return;
      status = useGateway ? '通过本机网关播放 · 分片缓存已启用' : '受控直传播放 · 不缓存';
    } catch (_) {
      if (generation == _generation) status = '媒体打开失败，请检查地址并重试';
    } finally {
      if (generation == _generation) {
        opening = false;
        notifyListeners();
      }
    }
  }

  void setGateway(bool value) {
    useGateway = value;
    notifyListeners();
  }

  void toggleTelevision() {
    television = !television;
    notifyListeners();
  }

  void toggleTheme() {
    dark = !dark;
    notifyListeners();
  }

  Future<void> shutdown() async {
    _generation++;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await engine.dispose();
    await gateway?.close();
    // Delete only this process's uniquely-created disposable cache directory.
    if (await _cacheDirectory?.exists() ?? false) {
      await _cacheDirectory!.delete(recursive: true);
    }
    dispose();
  }
}
