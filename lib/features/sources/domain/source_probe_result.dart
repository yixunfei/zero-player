import '../../../core/network/document_client.dart';

enum SourceProbeState { available, unavailable, inconclusive, cancelled }

SourceProbeState classifyProbeFailure(RemoteFailure failure) =>
    switch (failure.kind) {
      FailureKind.cancelled => SourceProbeState.cancelled,
      FailureKind.invalid ||
      FailureKind.unsupported => SourceProbeState.unavailable,
      FailureKind.http
          when {400, 401, 403, 404, 405, 410, 422}.contains(failure.status) =>
        SourceProbeState.unavailable,
      _ => SourceProbeState.inconclusive,
    };
