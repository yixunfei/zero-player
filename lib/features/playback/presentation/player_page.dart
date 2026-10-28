import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import '../../../app/app_services.dart';
import '../../../app/widgets.dart';
import '../../../core/platform/file_transfer.dart';
import '../../../media/engine/media_kit_engine.dart';
import '../../catalog/domain/catalog_item.dart';
import '../application/playback_controller.dart';
import 'source_switch.dart';
import 'probe_dialog.dart';
import 'timeline_slider.dart';
import 'skip_marks_dialog.dart';
import 'playback_surface.dart';
import 'quality_selector.dart';
import 'line_selector.dart';
import '../../sources/presentation/block_source_button.dart';

final class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.services, required this.request});
  final AppServices services;
  final PlaybackRequest request;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

final class _PlayerPageState extends State<PlayerPage>
    with WidgetsBindingObserver {
  late final MediaKitEngine engine;
  late final PlaybackController controller;
  bool fullscreen = false;
  bool locked = false;
  bool leaving = false;
  bool closed = false;
  late final void Function() _removeCloseHook;
  BoxFit fit = BoxFit.contain;
  @override
  void initState() {
    super.initState();
    engine = MediaKitEngine();
    controller = PlaybackController(widget.services, engine);
    _removeCloseHook = widget.services.addCloseHook(controller.close);
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.open(widget.request));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(controller.endSpeed());
      unawaited(controller.save());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeCloseHook();
    if (!closed) unawaited(controller.close());
    unawaited(widget.services.platform.fullscreen(false));
    super.dispose();
  }

  Future<void> _leave() async {
    if (locked) {
      setState(() => locked = false);
      return;
    }
    if (fullscreen) {
      await _fullscreen();
      return;
    }
    if (leaving) return;
    leaving = true;
    // Stop notifications before disposing the controller that builds this page.
    if (mounted) setState(() => closed = true);
    await controller.close();
    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    }
  }

  Future<void> _fullscreen() async {
    if (locked) return;
    await widget.services.platform.fullscreen(!fullscreen);
    if (mounted) setState(() => fullscreen = !fullscreen);
  }

  @override
  Widget build(BuildContext context) {
    if (closed) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): () =>
              locked ? null : controller.toggle(),
          const SingleActivator(LogicalKeyboardKey.escape): _leave,
          const SingleActivator(LogicalKeyboardKey.keyF): _fullscreen,
          const SingleActivator(LogicalKeyboardKey.keyJ): () => locked
              ? null
              : controller.seek(
                  controller.originalPosition - const Duration(seconds: 10),
                ),
          const SingleActivator(LogicalKeyboardKey.keyL): () => locked
              ? null
              : controller.seek(
                  controller.originalPosition + const Duration(seconds: 10),
                ),
        },
        child: Focus(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) =>
                Scaffold(backgroundColor: Colors.black, body: _video()),
          ),
        ),
      ),
    );
  }

  Widget _video() => Theme(
    data: ThemeData.dark(useMaterial3: true),
    child: PlaybackSurface(
      controller: controller,
      video: Video(
        controller: engine.video,
        controls: NoVideoControls,
        fit: fit,
      ),
      transport: _transport(),
      title: controller.request?.item.title ?? widget.request.item.title,
      onBack: _leave,
      onOptions: _showOptions,
      locked: locked,
      onLock: (value) {
        controller.endSpeed();
        setState(() => locked = value);
      },
      gestures: widget.services.settings.value.gestures,
      errorAction:
          controller.request?.offline == null && controller.request != null
          ? BlockSourceButton(
              name: '当前播放来源',
              onBlock: () => widget.services.sources.setEnabled(
                controller.request!.item.sourceId,
                false,
              ),
            )
          : null,
    ),
  );

  Future<void> _showOptions() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SingleChildScrollView(child: _controls()),
      ),
    ),
  );

  Widget _controls() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      children: [
        if (controller.error != null && controller.request?.offline == null)
          BlockSourceButton(
            name: '当前播放来源',
            onBlock: () => widget.services.sources.setEnabled(
              controller.request!.item.sourceId,
              false,
            ),
          ),
        if (controller.request != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${controller.line.name} · ${controller.episode.label}',
            ),
          ),
        if (controller.notice != null)
          ListTile(
            title: Text(controller.notice!),
            trailing: controller.canCancelRecovery
                ? TextButton(
                    onPressed: () => setState(controller.cancelRecovery),
                    child: const Text('停止恢复'),
                  )
                : controller.canUndoSkip
                ? TextButton(
                    onPressed: controller.undoSkip,
                    child: const Text('撤销跳过'),
                  )
                : null,
          ),
        _playbackOptions(),
        if (controller.request != null && controller.request!.offline == null)
          _episodes(),
      ],
    ),
  );
  Widget _playbackOptions() => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      OutlinedButton(
        onPressed: () => setState(
          () => fit = fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain,
        ),
        child: Text(fit == BoxFit.contain ? '原始比例' : '填满画面'),
      ),
      OutlinedButton(
        onPressed: () => perform(context, () async {
          if (!await widget.services.platform.pictureInPicture()) {
            throw StateError('当前设备不支持画中画');
          }
        }),
        child: const Text('小窗'),
      ),
      OutlinedButton(onPressed: _screenshot, child: const Text('截图')),
      if (controller.request?.offline == null)
        OutlinedButton(
          onPressed: () => selectQuality(context, controller),
          child: const Text('选择画质'),
        ),
      if (controller.request?.offline == null)
        OutlinedButton(
          onPressed: () => showMediaProbe(
            context,
            widget.services,
            controller,
            '${engine.player.state.width ?? 0} × ${engine.player.state.height ?? 0}',
          ),
          child: const Text('测速 / 画质'),
        ),
      if (!controller.isLive && controller.request?.offline == null) ...[
        OutlinedButton(
          onPressed: () => perform(context, controller.mark),
          child: Text(controller.markStart == null ? '标记片段起点' : '标记终点并保存'),
        ),
        OutlinedButton(
          onPressed: () => showSkipMarks(context, widget.services, controller),
          child: const Text('管理片段'),
        ),
        OutlinedButton(
          onPressed: () =>
              switchPlaybackSource(context, widget.services, controller),
          child: const Text('换源续播'),
        ),
      ],
    ],
  );
  Widget _rate() => PopupMenuButton<double>(
    tooltip: '倍速',
    initialValue: controller.state.rate,
    onSelected: engine.setRate,
    itemBuilder: (_) => [
      for (final rate in [.5, .75, 1.0, 1.25, 1.5, 2.0])
        PopupMenuItem(value: rate, child: Text('${rate}x')),
    ],
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text('${controller.state.rate}x'),
    ),
  );
  Widget _volume() => SizedBox(
    width: 150,
    child: Row(
      children: [
        IconButton(
          tooltip: controller.state.volume == 0 ? '取消静音' : '静音',
          onPressed: () =>
              engine.setVolume(controller.state.volume == 0 ? 60 : 0),
          icon: Icon(
            controller.state.volume == 0 ? Icons.volume_off : Icons.volume_up,
          ),
        ),
        Expanded(
          child: Slider(
            value: controller.state.volume.clamp(0, 100),
            max: 100,
            semanticFormatterCallback: (value) => '音量 ${value.round()}%',
            onChanged: engine.setVolume,
          ),
        ),
      ],
    ),
  );
  Widget _transport() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!controller.isLive)
        Row(
          children: [
            Text(clockText(controller.originalPosition)),
            Expanded(
              child: TimelineSlider(
                position: controller.originalPosition,
                duration: controller.originalDuration,
                marks: controller.marks,
                seek: controller.seek,
              ),
            ),
            Text(clockText(controller.originalDuration)),
          ],
        ),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _volume(),
          _rate(),

          IconButton(
            tooltip: '后退 10 秒',
            onPressed: controller.isLive
                ? null
                : () => controller.seek(
                    controller.originalPosition - const Duration(seconds: 10),
                  ),
            icon: const Icon(Icons.replay_10),
          ),
          FilledButton.tonalIcon(
            onPressed: controller.busy ? null : controller.toggle,
            icon: Icon(
              controller.state.playing ? Icons.pause : Icons.play_arrow,
            ),
            label: Text(controller.state.playing ? '暂停' : '播放'),
          ),
          IconButton(
            tooltip: '前进 10 秒',
            onPressed: controller.isLive
                ? null
                : () => controller.seek(
                    controller.originalPosition + const Duration(seconds: 10),
                  ),
            icon: const Icon(Icons.forward_10),
          ),
          IconButton(
            tooltip: '下一集 / 频道',
            onPressed: controller.request == null
                ? null
                : controller.nextEpisode,
            icon: const Icon(Icons.skip_next),
          ),
          IconButton(
            tooltip: fullscreen ? '退出全屏' : '全屏',
            onPressed: _fullscreen,
            icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
          ),
          IconButton(
            tooltip: '显示选集与设置',
            onPressed: _showOptions,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
    ],
  );
  Widget _episodes() => Column(
    children: [
      LineSelector(
        key: ValueKey(
          '${controller.request!.item.sourceId}/${controller.request!.item.id}',
        ),
        services: widget.services,
        item: controller.request!.item,
        selected: controller.request!.line,
        episodeLabel: controller.episode.label,
        headers: controller.request!.headers,
        headersByUri: controller.request!.headersByUri,
        onSelected: _line,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        children: [
          for (var i = 0; i < controller.line.episodes.length; i++)
            ChoiceChip(
              label: Text(controller.line.episodes[i].label),
              selected: controller.request!.episode == i,
              onSelected: (_) => controller.select(controller.request!.line, i),
            ),
        ],
      ),
    ],
  );
  Future<void> _line(int index) async {
    final target = controller.request!.item.lines[index];
    final matches = matchingEpisodes(controller.episode.label, target.episodes);
    if (matches.length == 1) {
      await controller.select(
        index,
        matches.single,
        position: controller.originalPosition,
      );
    } else {
      final selected = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('无法唯一匹配剧集，请选择'),
          children: [
            for (var i = 0; i < target.episodes.length; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, i),
                child: Text(target.episodes[i].label),
              ),
          ],
        ),
      );
      if (selected != null) await controller.select(index, selected);
    }
  }

  Future<void> _screenshot() => perform(context, () async {
    final bytes = await engine.screenshot();
    if (bytes == null) throw StateError('当前没有可截图的视频帧');
    final file = File(
      p.join(
        widget.services.root.path,
        'screenshot-${DateTime.now().millisecondsSinceEpoch}.jpg',
      ),
    );
    try {
      await file.writeAsBytes(bytes);
      await FileTransfer.saveFile(file, p.basename(file.path), 'image/jpeg');
    } finally {
      if (await file.exists()) await file.delete();
    }
  });
}
