/// Cleanup failures must not strand an already closed player on its loading page.
Future<void> finishPlayerExit({
  required Future<void> Function() close,
  required Future<void> Function() restore,
  required void Function() navigate,
  required void Function(Object, StackTrace) report,
}) async {
  final failures = <(Object, StackTrace)>[];
  for (final step in [close, restore]) {
    try {
      await step();
    } catch (error, stack) {
      failures.add((error, stack));
    }
  }
  navigate();
  for (final failure in failures) {
    report(failure.$1, failure.$2);
  }
}
