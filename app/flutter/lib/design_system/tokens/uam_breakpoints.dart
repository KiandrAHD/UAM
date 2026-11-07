/// Responsive breakpoints copied from the Figma implementation.
///
/// Flutter logical pixels are used 1:1 with the CSS pixel values in
/// `design_uam.md`; the mapping is documented in docs/PHASE_1_REPORT.md.
abstract final class UamBreakpoints {
  /// Maximum width of the compact card adaptation.
  static const double compact = 390;

  /// Maximum width of the mobile shell.
  static const double mobile = 760;

  /// Maximum width of the icon-only tablet shell.
  static const double tablet = 1100;

  /// Desktop content maximum width.
  static const double contentMax = 1500;

  /// Sidebar width on desktop.
  static const double sidebarDesktop = 238;

  /// Sidebar width on tablet.
  static const double sidebarTablet = 76;

  /// Desktop and tablet top bar height.
  static const double topBarDesktop = 78;

  /// Mobile top bar height.
  static const double topBarMobile = 60;

  /// Mobile bottom navigation height, excluding safe-area padding.
  static const double bottomNavigation = 70;

  /// Device-manager permission panel width.
  static const double permissionPanel = 300;

  /// Equalizer side rail width.
  static const double equalizerRail = 270;

  /// Settings category list width.
  static const double settingsNavigation = 220;

  /// Settings content cap.
  static const double settingsContent = 750;
}

/// Coarse width classes used by feature layouts.
enum UamWidthClass { compact, mobile, tablet, desktop }

/// Resolve the shell width class from available logical pixels.
UamWidthClass uamWidthClassFor(double width) {
  if (width <= UamBreakpoints.compact) {
    return UamWidthClass.compact;
  }
  if (width <= UamBreakpoints.mobile) {
    return UamWidthClass.mobile;
  }
  if (width <= UamBreakpoints.tablet) {
    return UamWidthClass.tablet;
  }
  return UamWidthClass.desktop;
}

/// Whether a shell shows persistent desktop navigation.
bool uamUsesSidebar(UamWidthClass widthClass) =>
    widthClass == UamWidthClass.desktop || widthClass == UamWidthClass.tablet;

/// Whether a shell shows mobile navigation.
bool uamUsesMobileNavigation(UamWidthClass widthClass) =>
    widthClass == UamWidthClass.compact || widthClass == UamWidthClass.mobile;
