import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../../media/gateway/offline_server.dart';
import '../../playback/domain/player_engine.dart';
import '../data/books_repository.dart';
import '../domain/book.dart';

final class AudiobookPlayerPage extends StatefulWidget {
  const AudiobookPlayerPage({
    super.key,
    required this.services,
    required this.book,
    required this.chapters,
    required this.initial,
  });
  final AppServices services;
  final Book book;
  final List<BookChapter> chapters;
  final BookChapter initial;

  @override
  State<AudiobookPlayerPage> createState() => _AudiobookPlayerPageState();
}

final class _AudiobookPlayerPageState extends State<AudiobookPlayerPage> {
  late BookChapter _chapter = widget.initial;
  PlayerEngine? _engine;
  OfflineSession? _session;
  CancellationToken? _token;
  StreamSubscription<PlaybackSnapshot>? _states;
  StreamSubscription<String>? _errors;
  Future<void>? _loading;
  Future<void>? _shutdown;
  final _playback = ValueNotifier(const PlaybackSnapshot());
  String? _error;
  bool _busy = true;
  double _rate = 1;
  double? _resumeMs;
  int _savedAt = 0;
  int get _index => widget.chapters.indexOf(_chapter);
  BooksRepository get _books => widget.services.books;

  @override
  void initState() {
    super.initState();
    _books.policy.addListener(_policyChanged);
    widget.services.setAudiobookControls(pause: _pause, close: _close);
    _start(widget.initial, resume: true);
  }

  void _policyChanged() {
    if (_books.kindAllowed(BookKind.audio) &&
        _books.bookAllowed(widget.book) &&
        _books.policy.textAllowed(_chapter.title)) {
      return;
    }
    _token?.cancel();
    unawaited(_pause());
    if (mounted) setState(() => _error = '当前内容策略限制播放该章节');
  }

  Future<void> _pause() async {
    if (_busy) _token?.cancel();
    final engine = _engine;
    if (engine != null) await engine.pause();
  }

  void _start(BookChapter chapter, {bool resume = false}) {
    if (_loading != null || _shutdown != null) return;
    final pending = _open(chapter, resume: resume);
    _loading = pending;
    unawaited(
      pending.whenComplete(() {
        _loading = null;
        if (mounted) setState(() => _busy = false);
      }),
    );
  }

  Future<void> _open(BookChapter chapter, {required bool resume}) async {
    _save();
    final token = _token = CancellationToken();
    setState(() {
      _chapter = chapter;
      _error = null;
      _busy = true;
    });
    _playback.value = const PlaybackSnapshot();
    _resumeMs = null;
    try {
      await _engine?.stop();
      _session?.close();
      _session = null;
      _books.requireBook(widget.book, chapter);
      final old = await _books.store.entry(widget.book);
      if (!await _books.audioFiles.contains(widget.book, chapter)) {
        await _books.download(widget.book, chapter, token);
      }
      token.check();
      _books.requireBook(widget.book, chapter);
      final session = _session = await _books.audioFiles.open(
        widget.book,
        chapter,
      );
      token.check();
      await widget.services.pauseForAudiobook();
      token.check();
      _books.requireBook(widget.book, chapter);
      final engine = _engine ??= _createEngine();
      await engine.open(session.uri);
      token.check();
      _books.requireBook(widget.book, chapter);
      await engine.setRate(_rate);
      if (resume && old?.last == chapter.id && old!.position > 0) {
        _resumeMs = old.position;
        _restorePosition(engine.snapshot);
      }
      await _books.store.saveBook(
        widget.book,
        chapters: widget.chapters,
        last: chapter,
        position: old?.last == chapter.id ? old?.position ?? 0 : 0,
      );
    } on RequestCancelled {
      if (mounted && _error == null) setState(() => _error = '已取消加载音频');
    } on FormatException catch (error) {
      if (mounted && !token.isCancelled) setState(() => _error = error.message);
    } on RemoteFailure catch (error) {
      if (mounted && !token.isCancelled) setState(() => _error = error.message);
    } catch (_) {
      if (mounted && !token.isCancelled) setState(() => _error = '无法打开音频或内容受限');
    }
  }

  PlayerEngine _createEngine() {
    final engine = widget.services.createAudiobookEngine();
    _states = engine.states.listen((value) {
      if (!mounted || _shutdown != null) return;
      _playback.value = value;
      if (_busy) return;
      _restorePosition(value);
      final seconds = value.position.inSeconds;
      if ((seconds - _savedAt).abs() >= 5) {
        _savedAt = seconds;
        _save();
      }
    });
    _errors = engine.errors.listen((_) {
      if (mounted) setState(() => _error = '音频解码失败，请换源或重新下载');
    });
    return engine;
  }

  void _restorePosition(PlaybackSnapshot state) {
    final position = _resumeMs;
    if (position == null || state.duration <= Duration.zero) return;
    _resumeMs = null;
    final target = position.round().clamp(0, state.duration.inMilliseconds);
    unawaited(_engine?.seek(Duration(milliseconds: target)));
  }

  void _save() {
    if (_session == null || _engine == null || _busy) return;
    final position = _engine!.snapshot.position.inMilliseconds.toDouble();
    unawaited(
      _books.store
          .saveBook(widget.book, last: _chapter, position: position)
          .onError((_, _) {}),
    );
  }

  Future<void> _close() => _shutdown ??= _release();

  Future<void> _release() async {
    _token?.cancel();
    await _loading;
    await _states?.cancel();
    await _errors?.cancel();
    try {
      await _engine?.dispose();
    } finally {
      _session?.close();
    }
  }

  @override
  void dispose() {
    _save();
    widget.services.setAudiobookControls();
    _books.policy.removeListener(_policyChanged);
    unawaited(_close());
    _playback.dispose();
    super.dispose();
  }

  String _time(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${hours == 0 ? '' : '$hours:'}$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                Icons.headphones_outlined,
                size: 88,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                _chapter.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      LinearProgressIndicator(),
                      SizedBox(height: 12),
                      Text('正在准备音频章节…'),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              ValueListenableBuilder<PlaybackSnapshot>(
                valueListenable: _playback,
                builder: (_, state, _) => _controls(state),
              ),
              if (!_busy &&
                  _error != null &&
                  _books.kindAllowed(BookKind.audio))
                Center(
                  child: OutlinedButton(
                    onPressed: () => _start(_chapter, resume: true),
                    child: const Text('重试'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls(PlaybackSnapshot state) {
    final active = !_busy && _error == null && _session != null;
    final duration = state.duration.inMilliseconds;
    return Column(
      children: [
        Slider(
          value: state.position.inMilliseconds.clamp(0, duration).toDouble(),
          max: duration > 0 ? duration.toDouble() : 1,
          onChanged: !active || duration <= 0
              ? null
              : (value) => _engine?.seek(Duration(milliseconds: value.round())),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(_time(state.position)), Text(_time(state.duration))],
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.center,
          children: [
            IconButton(
              tooltip: '上一章',
              icon: const Icon(Icons.skip_previous),
              onPressed: !_busy && _index > 0
                  ? () => _start(widget.chapters[_index - 1])
                  : null,
            ),
            IconButton.filled(
              tooltip: state.playing ? '暂停' : '播放',
              icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
              onPressed: active
                  ? () async {
                      _books.requireBook(widget.book, _chapter);
                      if (!state.playing) {
                        await widget.services.pauseForAudiobook();
                      }
                      if (mounted && _books.kindAllowed(BookKind.audio)) {
                        await _engine?.playOrPause();
                      }
                    }
                  : null,
            ),
            IconButton(
              tooltip: '下一章',
              icon: const Icon(Icons.skip_next),
              onPressed: !_busy && _index + 1 < widget.chapters.length
                  ? () => _start(widget.chapters[_index + 1])
                  : null,
            ),
            DropdownButton<double>(
              value: _rate,
              items: [
                for (final rate in [.75, 1.0, 1.25, 1.5, 2.0])
                  DropdownMenuItem(
                    value: rate,
                    child: Text(
                      '${rate.toStringAsFixed(rate == 1 || rate == 2 ? 0 : 2)}×',
                    ),
                  ),
              ],
              onChanged: !active
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _rate = value);
                      unawaited(_engine?.setRate(value));
                    },
            ),
          ],
        ),
      ],
    );
  }
}
