/// Optional native diagnostics and decoder recovery for video-capable engines.
abstract interface class VideoRecoveryEngine {
  Future<void> useSoftwareDecoder();
  Future<Map<String, Object?>> readVideoDiagnostics();
}
