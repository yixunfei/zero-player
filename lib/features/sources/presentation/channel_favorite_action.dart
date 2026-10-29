import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/widgets.dart';
import '../data/source_repository.dart';
import '../domain/video_source.dart';

/// Detail pages observe the same persisted preference as source management.
final class ChannelFavoriteAction extends StatefulWidget {
  const ChannelFavoriteAction({
    super.key,
    required this.sourceId,
    required this.repository,
  });
  final String sourceId;
  final SourceRepository repository;
  @override
  State<ChannelFavoriteAction> createState() => _ChannelFavoriteActionState();
}

final class _ChannelFavoriteActionState extends State<ChannelFavoriteAction> {
  StreamSubscription<void>? _subscription;
  VideoSource? _source;
  bool _saving = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _observe();
  }

  void _observe() {
    _subscription = widget.repository.changes.listen((_) => _reload());
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final revision = ++_revision;
    try {
      final source = await widget.repository.find(widget.sourceId);
      if (mounted && revision == _revision) setState(() => _source = source);
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _source = null);
    }
  }

  @override
  void didUpdateWidget(ChannelFavoriteAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.sourceId != widget.sourceId) {
      _subscription?.cancel();
      _source = null;
      _observe();
    }
  }

  Future<void> _toggle() => perform(context, () async {
    final source = _source;
    if (_saving || source == null) return;
    setState(() => _saving = true);
    try {
      await widget.repository.favorite(source.id, !source.favorite);
      await _reload();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _source == null || _saving ? null : _toggle,
    icon: Icon(_source?.favorite == true ? Icons.star : Icons.star_outline),
    label: Text(_source?.favorite == true ? '已收藏渠道' : '收藏该渠道'),
  );

  @override
  void dispose() {
    _revision++;
    _subscription?.cancel();
    super.dispose();
  }
}
