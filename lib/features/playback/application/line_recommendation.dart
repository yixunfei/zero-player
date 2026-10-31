import '../../../media/network/media_probe.dart';

/// Prefer responsive media while avoiding known low resolution variants.
/// A missing resolution is unknown, never evidence of high definition.
int compareLineResponses(ProbeResult a, ProbeResult b) {
  int lowResolution(ProbeResult value) {
    final height = int.tryParse(value.resolution?.split('x').last ?? '');
    return height != null && height < 480 ? 1 : 0;
  }

  final quality = lowResolution(a).compareTo(lowResolution(b));
  if (quality != 0) return quality;
  return a.firstByte.compareTo(b.firstByte);
}
