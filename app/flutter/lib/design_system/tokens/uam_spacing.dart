/// Observed UAM spacing rhythm from `design_uam.md`, with named steps.
abstract final class UamSpacing {
  /// 2px: tight metadata separation.
  static const double xxs = 2;

  /// 3px: segmented inset.
  static const double tiny = 3;

  /// 4px: tight gaps.
  static const double xs = 4;

  /// 6px: compact control gaps.
  static const double sm = 6;

  /// 8px: standard compact gap.
  static const double md = 8;

  /// 10px: icon/text gap.
  static const double mdPlus = 10;

  /// 12px: compact padding.
  static const double lg = 12;

  /// 14px: grid gap.
  static const double lgPlus = 14;

  /// 16px: standard grid gap.
  static const double xl = 16;

  /// 20px: standard card padding.
  static const double xxl = 20;

  /// 24px: modal padding and large grouping.
  static const double huge = 24;

  /// 32px: page-level spacing.
  static const double page = 32;

  /// 34px: desktop horizontal page padding.
  static const double pageWide = 34;

  /// 50px: large empty-state vertical padding.
  static const double empty = 50;

  /// 70px: desktop bottom content padding.
  static const double desktopBottom = 70;

  /// 94px: mobile bottom content padding.
  static const double mobileBottom = 94;

  /// Desktop content maximum width.
  static const double maxContentWidth = 1500;
}
