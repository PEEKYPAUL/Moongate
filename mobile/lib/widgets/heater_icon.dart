import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Shared bits for the printer temperature icons (hotend / bed / chamber).
///
/// The hotend (Material Design Icons `printer-3d-nozzle`) and the bed
/// (`radiator`) are font glyphs via [AppIcons]; the chamber is a small custom
/// SVG (a box with a fan) because MDI has no matching glyph. All three are
/// drawn through [heaterIcon] so a call site does not care which kind it is.

/// The custom chamber icon asset (a box with a fan). Rendered with flutter_svg
/// and tinted at the call site like any other icon. Used where the icon stays
/// still (the preheat sheet, the UI guide); the dashboard uses the animated
/// [ChamberFanIcon], which draws the two split layers below.
const String kChamberIconAsset = 'assets/icons/chamber.svg';

/// The static layer of the chamber icon: the box and the fan housing circle.
const String kChamberFrameAsset = 'assets/icons/chamber_frame.svg';

/// The spinning layer of the chamber icon: the three fan blades and the hub.
const String kChamberBladesAsset = 'assets/icons/chamber_blades.svg';

/// Colour a hotend or bed icon takes while its heater is hot or heating, so it
/// reads like Duet's red heated icons. The chamber icon never uses this.
const Color kHeaterHotColour = Color(0xFFE53935);

/// At or above this temperature (Celsius) a heater counts as hot even with no
/// target set, so a nozzle or bed that is cooling down still reads as hot.
const double kWarmThresholdCelsius = 50;

/// Whether a heater should read as hot: it has a target set, or its current
/// temperature is still above [kWarmThresholdCelsius].
bool heaterIsHot(double temp, double target) =>
    target > 0 || temp >= kWarmThresholdCelsius;

/// A temperature-cell icon: the font glyph [icon], or the custom chamber SVG
/// when [asset] is given. Tinted to [color] and sized to [size].
Widget heaterIcon({
  IconData? icon,
  String? asset,
  required double size,
  required Color color,
}) {
  if (asset != null) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
  return Icon(icon, size: size, color: color);
}
