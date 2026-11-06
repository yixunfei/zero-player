import 'dart:async';

/// Cleanup failures must not strand an already closed player on its loading page.
Future<void> finishPlayerExit({
  required Future<void> Function() close,
  required Future<void> Function() restore,
  required void Function() navigate,
  required void Function(Object, StackTrace) report,
  Duration stepTimeout = const Duration(seconds: 6),
}) async {
  final failures = <(Object, StackTrace)>[];
  for (final step in [close, restore]) {
    try {
      await step().timeout(stepTimeout);
    } catch (error, stack) {
      failures.add((error, stack));
    }
  }
  navigate();
  for (final failure in failures) {
    report(failure.$1, failure.$2);
  }
}
