import 'package:flutter/widgets.dart';
import '../core/platform/platform_services.dart';

/// Phone landscape keeps phone navigation; a saved TV preference cannot hide it.
bool usesCompactNavigation(BuildContext context, PlatformServices platform) {
  if (platform.television) return false;
  final size = MediaQuery.sizeOf(context);
  return size.width < 700 || (platform.mobile && size.shortestSide < 600);
}
