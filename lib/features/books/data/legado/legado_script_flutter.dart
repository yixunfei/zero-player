import 'package:flutter_qjs_next/flutter_qjs.dart';

({Object? value, List<Object?> requests, bool failed}) evaluateLegadoScript(
  String setup,
  String script,
) {
  final runtime = QuickJsRuntime2(
    timeout: 160,
    memoryLimit: 24 * 1024 * 1024,
    stackSize: 256 * 1024,
    autoExecutePendingJobs: false,
    webApis: const JsWebApis.none(),
  );
  try {
    final initial = runtime.evaluate(setup);
    if (initial.isError) return (value: null, requests: const [], failed: true);
    Object? value;
    var failed = false;
    try {
      value = runtime.evaluateJson(script);
    } on Object {
      failed = true;
    }
    final requests = runtime.evaluateJson('__zpLegadoRequests()');
    return (
      value: value,
      requests: requests is List ? requests : const [],
      failed: failed,
    );
  } on Object {
    return (value: null, requests: const [], failed: true);
  } finally {
    runtime.dispose();
  }
}
