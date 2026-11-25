import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays its children side by side in equal widths and one height,
/// leaving out the ones that show nothing (a card with nothing to say
/// is zero high), so the shown ones share the whole row (owner request
/// 2026-11-25: Tomorrow, the last order and the cut-off in one line).
class EvenRow extends MultiChildRenderObjectWidget {
  const EvenRow({super.key, this.spacing = 12, required super.children});

  final double spacing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderEvenRow(spacing);

  @override
  void updateRenderObject(BuildContext context, RenderEvenRow renderObject) {
    renderObject.spacing = spacing;
  }
}

class EvenRowParentData extends ContainerBoxParentData<RenderBox> {}

class RenderEvenRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, EvenRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, EvenRowParentData> {
  RenderEvenRow(this._spacing);

  double _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! EvenRowParentData) {
      child.parentData = EvenRowParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final shown = <RenderBox>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      (child.parentData! as EvenRowParentData).offset = Offset.zero;
      if (child.size.height > 0) shown.add(child);
    }
    if (shown.isEmpty) {
      size = constraints.constrain(Size(width, 0));
      return;
    }
    final each = (width - _spacing * (shown.length - 1)) / shown.length;
    var height = 0.0;
    for (final child in shown) {
      child.layout(BoxConstraints.tightFor(width: each), parentUsesSize: true);
      height = math.max(height, child.size.height);
    }
    for (var i = 0; i < shown.length; i++) {
      shown[i].layout(BoxConstraints.tightFor(width: each, height: height));
      (shown[i].parentData! as EvenRowParentData).offset = Offset(
        i * (each + _spacing),
        0,
      );
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// [child] with [gap] below it, or nothing at all when [child] shows
/// nothing (zero high): cards one under the other without stray gaps.
class GapBelow extends SingleChildRenderObjectWidget {
  const GapBelow({super.key, this.gap = 10, required super.child});

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGapBelow(gap);

  @override
  void updateRenderObject(BuildContext context, RenderGapBelow renderObject) {
    renderObject.gap = gap;
  }
}

class RenderGapBelow extends RenderShiftedBox {
  RenderGapBelow(this._gap) : super(null);

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints.copyWith(minHeight: 0), parentUsesSize: true);
    (child.parentData! as BoxParentData).offset = Offset.zero;
    final h = child.size.height;
    size = constraints.constrain(
      Size(constraints.maxWidth, h > 0 ? h + _gap : 0),
    );
  }
}
