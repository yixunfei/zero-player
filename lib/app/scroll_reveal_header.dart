import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reveals a naturally sized header on upward scrolling, without scroll-stop
/// callbacks reading child dimensions while the viewport is laying out.
final class ScrollRevealHeader extends SingleChildRenderObjectWidget {
  const ScrollRevealHeader({super.key, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRevealHeader();
}

final class _RenderRevealHeader extends RenderSliverSingleBoxAdapter {
  double? _previousOffset;
  double _extent = 0;
  double _hidden = 0;

  @override
  void performLayout() {
    child?.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final oldExtent = _extent;
    _extent = child == null
        ? 0
        : switch (constraints.axis) {
            Axis.vertical => child!.size.height,
            Axis.horizontal => child!.size.width,
          };
    final offset = constraints.scrollOffset;
    final delta = offset - (_previousOffset ?? 0);
    if (_previousOffset == null || offset <= 0) {
      _hidden = offset.clamp(0.0, _extent);
    } else {
      if (oldExtent > 0 && _hidden >= oldExtent) _hidden = _extent;
      if (delta < 0) {
        _hidden = 0;
      } else {
        _hidden = (_hidden + delta).clamp(0.0, _extent);
      }
    }
    _previousOffset = offset;
    final painted = (_extent - _hidden).clamp(
      0.0,
      constraints.remainingPaintExtent,
    );
    geometry = SliverGeometry(
      scrollExtent: _extent,
      paintOrigin: math.min(constraints.overlap, 0.0),
      paintExtent: painted,
      layoutExtent: (_extent - offset).clamp(0.0, painted),
      maxPaintExtent: _extent,
      hasVisualOverflow: true,
    );
    if (child != null) _positionChild();
  }

  void _positionChild() {
    final data = child!.parentData! as SliverPhysicalParentData;
    data.paintOffset = switch (applyGrowthDirectionToAxisDirection(
      constraints.axisDirection,
      constraints.growthDirection,
    )) {
      AxisDirection.down => Offset(0, -_hidden),
      AxisDirection.right => Offset(-_hidden, 0),
      AxisDirection.up => Offset(0, geometry!.paintExtent - _extent + _hidden),
      AxisDirection.left => Offset(
        geometry!.paintExtent - _extent + _hidden,
        0,
      ),
    };
  }

  @override
  double childMainAxisPosition(covariant RenderObject child) => -_hidden;
}
