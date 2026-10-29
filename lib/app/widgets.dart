import 'package:flutter/material.dart';
import '../core/network/document_client.dart';
export 'poster_card.dart';

void message(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> perform(
  BuildContext context,
  Future<void> Function() operation, {
  String? success,
}) async {
  try {
    await operation();
    if (context.mounted && success != null) message(context, success);
  } catch (error) {
    if (context.mounted) {
      message(
        context,
        error is FormatException
            ? error.message
            : error is RemoteFailure
            ? error.message
            : error is StateError
            ? error.message
            : '操作失败，请检查网络、文件和可用空间后重试',
      );
    }
  }
}

Future<bool> confirm(BuildContext context, String title, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;

Future<List<String>?> inputDialog(
  BuildContext context,
  String title,
  List<String> labels, {
  List<String>? initial,
  String action = '保存',
}) async {
  final controllers = List.generate(
    labels.length,
    (i) => TextEditingController(text: initial?[i] ?? ''),
  );
  final result = await showDialog<List<String>>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < labels.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextField(
                    controller: controllers[i],
                    autofocus: i == 0,
                    maxLines: labels[i].contains('JSON') ? 4 : 1,
                    decoration: InputDecoration(
                      labelText: labels[i],
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            controllers.map((c) => c.text.trim()).toList(),
          ),
          child: Text(action),
        ),
      ],
    ),
  );
  // Dialog exit animations may still refer to controllers this frame.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  for (final controller in controllers) {
    controller.dispose();
  }
  return result;
}

String clockText(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 9999999);
  return '${seconds ~/ 3600 > 0 ? '${seconds ~/ 3600}:' : ''}${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

final class EmptyState extends StatelessWidget {
  const EmptyState(
    this.title,
    this.description, {
    super.key,
    this.action,
    this.icon = Icons.movie_outlined,
  });
  final String title;
  final String description;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(description, textAlign: TextAlign.center),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 20), child: action),
        ],
      ),
    ),
  );
}

final class LoadView<T> extends StatelessWidget {
  const LoadView({
    super.key,
    required this.future,
    required this.builder,
    this.retry,
    this.errorAction,
  });
  final Future<T> future;
  final Widget Function(T) builder;
  final VoidCallback? retry;
  final Widget? errorAction;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done &&
          !snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return EmptyState(
          '暂时无法加载',
          '请检查网络和来源配置后重试',
          action: Wrap(
            spacing: 12,
            children: [
              if (retry != null)
                FilledButton(onPressed: retry, child: const Text('重试')),
              ?errorAction,
            ],
          ),
        );
      }
      return builder(snapshot.data as T);
    },
  );
}

final class PosterGrid extends StatelessWidget {
  const PosterGrid({super.key, required this.children, this.sliver = false})
    : itemCount = null,
      itemBuilder = null;
  const PosterGrid.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.sliver = false,
  }) : children = null;
  final List<Widget>? children;
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final bool sliver;
  @override
  Widget build(BuildContext context) {
    final delegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent:
          Theme.of(context).visualDensity == VisualDensity.comfortable
          ? 320
          : 220,
      childAspectRatio: .66,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    );
    if (sliver) {
      return SliverPadding(
        padding: const EdgeInsets.all(20),
        sliver: SliverGrid.builder(
          gridDelegate: delegate,
          itemCount: itemCount ?? children!.length,
          itemBuilder: itemBuilder ?? (_, index) => children![index],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: delegate,
      itemCount: itemCount ?? children!.length,
      itemBuilder: itemBuilder ?? (_, index) => children![index],
    );
  }
}
