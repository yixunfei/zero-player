import '../../core/network/cancellation_token.dart';

enum ExportFormat { mp4, ts }

final class ExportResult {
  const ExportResult(this.path, this.bytes, this.duration);
  final String path;
  final int bytes;
  final Duration duration;
}

abstract interface class MediaExporter {
  Future<ExportResult> export(
    Uri input,
    String output,
    ExportFormat format, {
    CancellationToken? cancellation,
  });
}
