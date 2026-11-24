import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'heater_icon.dart';

/// The chamber icon with a slowly, continuously spinning fan.
///
/// Two overlaid layers: a static frame (box + housing) and the three blades +
/// hub, which rotate. The spin runs whenever the icon is shown (Paul's choice),
/// regardless of printer state, so it is purely decorative. Reduced-motion
/// (MediaQuery.disableAnimations) stops it on a still frame.
///
/// Wrapped in a RepaintBoundary so the animation repaints only this icon, not
/// the whole dashboard tile. The Glance home-screen widget keeps its own still
/// drawable; only this Flutter icon animates.
class ChamberFanIcon extends StatefulWidget {
  final double size;
  final Color color;

  /// One full revolution per [period]. Slow and smooth by default.
  final Duration period;

  const ChamberFanIcon({
    required this.size,
    required this.color,
    this.period = const Duration(milliseconds: 4500),
    super.key,
  });

  @override
  State<ChamberFanIcon> createState() => _ChamberFanIconState();
}

class _ChamberFanIconState extends State<ChamberFanIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour the OS "reduce motion" setting: hold the blades still when it is
    // on, spin continuously otherwise.
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(); // 0 -> 1 on a loop = one clockwise turn per period
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ColorFilter.mode(widget.color, BlendMode.srcIn);
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SvgPicture.asset(kChamberFrameAsset, colorFilter: filter),
            RotationTransition(
              turns: _controller,
              child: SvgPicture.asset(kChamberBladesAsset, colorFilter: filter),
            ),
          ],
        ),
      ),
    );
  }
}
