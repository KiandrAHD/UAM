import 'package:flutter/material.dart';

/// Motion durations and curves.
///
/// Call sites must respect `MediaQuery.disableAnimations`; the app shell also
/// exposes an in-app reduced-motion preference.
abstract final class UamMotion {
  /// 0.18s: buttons.
  static const Duration button = Duration(milliseconds: 180);

  /// 0.20s: navigation, toggles, and control transitions.
  static const Duration control = Duration(milliseconds: 200);

  /// 0.2s: page content fade.
  static const Duration page = Duration(milliseconds: 200);

  /// Standard ease-out curve for short interactions.
  static const Curve standardCurve = Curves.easeOutCubic;
}
