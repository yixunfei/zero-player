import 'dart:async';

/// Attempt every cleanup in dependency order, then report the first failure.
Future<void> closeResources(
  Iterable<FutureOr<void> Function()> steps, {
  Duration stepTimeout = const Duration(seconds: 2),
}) async {
  Object? firstError;
  StackTrace? firstStack;
  for (final close in steps) {
    try {
      await Future<void>.sync(close).timeout(stepTimeout);
    } catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
  }
  if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
}
