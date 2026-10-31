import 'dart:io';
import 'package:path/path.dart' as p;
import '../../../app/app_services.dart';
import '../../../core/platform/video_files.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../sources/domain/video_source.dart';
import 'playback_controller.dart';
import '../data/local_video_repository.dart';

final class LocalVideo {
  static String? startupPath;

  static Future<PlaybackRequest> open(
    AppServices services,
    String path, {
    String? previousId,
    String? documentIdentity,
  }) async {
    if (!isLocalVideo(path)) throw const FormatException('请选择受支持的视频文件');
    final file = File(path);
    if (!await file.exists()) throw const FileSystemException('视频文件不存在或已移动');
    final canonical = await file.resolveSymbolicLinks();
    final id =
        (documentIdentity == null ? previousId : null) ??
        stableId(
          documentIdentity == null
              ? canonical
              : 'android-document:$documentIdentity',
        );
    final item = CatalogItem(
      sourceId: 'local',
      id: id,
      title: p.basename(path),
    );
    // Local files follow the same title and supervision boundary as online items.
    services.contentPolicy.requireItem(item);
    final previous = await services.history.latest('local', id);
    final session = await services.offline.openLocal(File(canonical));
    try {
      await LocalVideoRepository(services.db).remember(id, canonical);
    } catch (_) {
      session.close();
      rethrow;
    }
    return PlaybackRequest(
      CatalogItem(
        sourceId: 'local',
        id: id,
        title: item.title,
        lines: [
          PlayLine('本地视频', [Episode(item.title, session.uri)]),
        ],
      ),
      position:
          previous != null &&
              previous.position < previous.duration - const Duration(seconds: 5)
          ? previous.position
          : Duration.zero,
      offline: session,
      mediaKind: PlaybackMediaKind.local,
    );
  }
}
