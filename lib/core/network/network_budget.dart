import 'dart:async';
import 'cancellation_token.dart';

/// A deadline for active transport; scheduler queues consume no network budget.
final class NetworkBudget {
  NetworkBudget(this.limit, this.token, {this.onActivity});
  final Duration limit;
  final CancellationToken token;
  final void Function(bool)? onActivity;
  final clock = Stopwatch();
  Timer? _timer;
  void activity(bool active) {
    _timer?.cancel();
    if (active) {
      clock.start();
      final remaining = limit - clock.elapsed;
      if (remaining <= Duration.zero) {
        token.cancel();
      } else {
        _timer = Timer(remaining, token.cancel);
      }
    } else {
      clock.stop();
    }
    onActivity?.call(active);
  }

  void dispose() => activity(false);
}
