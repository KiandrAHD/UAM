import 'package:flutter/material.dart';

/// Raw UAM colour values extracted from `design_uam.md`.
///
/// Widgets must not reference these constants directly. Read
/// [UamColorTokens] from the active theme instead so light and dark surfaces
/// stay coherent.
abstract final class UamColors {
  // Dark application canvas and surfaces.
  static const Color background = Color(0xFF080C12);
  static const Color backgroundSecondary = Color(0xFF0C1119);
  static const Color surface = Color(0xFF111720);
  static const Color surfaceSecondary = Color(0xFF151D28);
  static const Color surfaceElevated = Color(0xFF1A2430);

  // Borders and text.
  static const Color border = Color(0xFF24303D);
  static const Color borderEmphasis = Color(0xFF344354);
  static const Color textPrimary = Color(0xFFF2F6FA);
  static const Color textSecondary = Color(0xFF96A5B5);
  static const Color textTertiary = Color(0xFF637283);

  // Brand and semantic state.
  static const Color accent = Color(0xFF2CBFF3);
  static const Color accentDark = Color(0xFF168BD4);
  static const Color success = Color(0xFF45D8A0);
  static const Color warning = Color(0xFFF0B35C);
  static const Color error = Color(0xFFF06E77);
  static const Color planned = Color(0xFFA797F6);
  static const Color destructiveText = Color(0xFFFF9AA1);

  // Fixed brand gradient.
  static const Color brandGradientStart = Color(0xFF22C6F8);
  static const Color brandGradientEnd = Color(0xFF1967D2);
  static const Color primaryButtonStart = Color(0xFF28BFF4);
  static const Color primaryButtonEnd = Color(0xFF168BD4);

  // Control wells and tracks.
  static const Color insetPanel = Color(0xFF0D131B);
  static const Color curveBackground = Color(0xFF111B25);
  static const Color toggleOff = Color(0xFF202A35);
  static const Color toggleOffThumb = Color(0xFF84919E);
  static const Color equalizerTrack = Color(0xFF2C3744);
  static const Color equalizerZeroLine = Color(0xFF526171);
  static const Color coreStatusWell = Color(0xFF0A0F16);

  // State overlays.
  static const Color infoOverlay = Color(0x0F2CBFF3);
  static const Color successOverlay = Color(0x1245D8A0);
  static const Color warningOverlay = Color(0x14F0B35C);
  static const Color errorOverlay = Color(0x14F06E77);
  static const Color plannedOverlay = Color(0x1AA797F6);
  static const Color scrim = Color(0xB3000000);
  static const Color modalShadow = Color(0xFF000000);

  // Light-theme counterparts. These are derived, not present in the Figma
  // source, and are documented in docs/PHASE_1_REPORT.md.
  static const Color lightBackground = Color(0xFFF3F6FA);
  static const Color lightBackgroundSecondary = Color(0xFFE9EEF6);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSecondary = Color(0xFFF1F5FA);
  static const Color lightSurfaceElevated = Color(0xFFE7EEF6);
  static const Color lightBorder = Color(0xFFD7E0EA);
  static const Color lightBorderEmphasis = Color(0xFFB9C7D6);
  static const Color lightTextPrimary = Color(0xFF0B1622);
  static const Color lightTextSecondary = Color(0xFF46586B);
  static const Color lightTextTertiary = Color(0xFF6B7C8E);
  static const Color lightAccent = Color(0xFF0B86B8);
  static const Color lightAccentDark = Color(0xFF0B6E99);
  static const Color lightSuccess = Color(0xFF147A54);
  static const Color lightWarning = Color(0xFF8A5A0A);
  static const Color lightError = Color(0xFFB3262E);
  static const Color lightPlanned = Color(0xFF6650C7);
  static const Color lightInsetPanel = Color(0xFFEDF2F7);
  static const Color lightCurveBackground = Color(0xFFF6F9FC);
  static const Color lightToggleOff = Color(0xFFD3DCE6);
  static const Color lightToggleOffThumb = Color(0xFF7C8B9A);
  static const Color lightEqualizerTrack = Color(0xFFD7E0EA);
  static const Color lightEqualizerZeroLine = Color(0xFF8A99A8);
  static const Color lightCoreStatusWell = Color(0xFFF0F4F8);
}

/// Semantic colour extension attached to both UAM themes.
@immutable
final class UamColorTokens extends ThemeExtension<UamColorTokens> {
  const UamColorTokens({
    required this.canvas,
    required this.canvasSecondary,
    required this.surface,
    required this.surfaceSecondary,
    required this.surfaceElevated,
    required this.border,
    required this.borderEmphasis,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentDark,
    required this.success,
    required this.warning,
    required this.error,
    required this.planned,
    required this.destructiveText,
    required this.onAccent,
    required this.insetPanel,
    required this.curveBackground,
    required this.toggleOff,
    required this.toggleOffThumb,
    required this.equalizerTrack,
    required this.equalizerZeroLine,
    required this.coreStatusWell,
    required this.infoOverlay,
    required this.successOverlay,
    required this.warningOverlay,
    required this.errorOverlay,
    required this.plannedOverlay,
    required this.scrim,
    required this.modalShadow,
    required this.isDark,
  });

  /// The exact Figma dark palette.
  static const UamColorTokens dark = UamColorTokens(
    canvas: UamColors.background,
    canvasSecondary: UamColors.backgroundSecondary,
    surface: UamColors.surface,
    surfaceSecondary: UamColors.surfaceSecondary,
    surfaceElevated: UamColors.surfaceElevated,
    border: UamColors.border,
    borderEmphasis: UamColors.borderEmphasis,
    textPrimary: UamColors.textPrimary,
    textSecondary: UamColors.textSecondary,
    textTertiary: UamColors.textTertiary,
    accent: UamColors.accent,
    accentDark: UamColors.accentDark,
    success: UamColors.success,
    warning: UamColors.warning,
    error: UamColors.error,
    planned: UamColors.planned,
    destructiveText: UamColors.destructiveText,
    onAccent: Color(0xFF041018),
    insetPanel: UamColors.insetPanel,
    curveBackground: UamColors.curveBackground,
    toggleOff: UamColors.toggleOff,
    toggleOffThumb: UamColors.toggleOffThumb,
    equalizerTrack: UamColors.equalizerTrack,
    equalizerZeroLine: UamColors.equalizerZeroLine,
    coreStatusWell: UamColors.coreStatusWell,
    infoOverlay: UamColors.infoOverlay,
    successOverlay: UamColors.successOverlay,
    warningOverlay: UamColors.warningOverlay,
    errorOverlay: UamColors.errorOverlay,
    plannedOverlay: UamColors.plannedOverlay,
    scrim: UamColors.scrim,
    modalShadow: UamColors.modalShadow,
    isDark: true,
  );

  /// Light counterpart preserving the same hierarchy and cyan identity.
  static const UamColorTokens light = UamColorTokens(
    canvas: UamColors.lightBackground,
    canvasSecondary: UamColors.lightBackgroundSecondary,
    surface: UamColors.lightSurface,
    surfaceSecondary: UamColors.lightSurfaceSecondary,
    surfaceElevated: UamColors.lightSurfaceElevated,
    border: UamColors.lightBorder,
    borderEmphasis: UamColors.lightBorderEmphasis,
    textPrimary: UamColors.lightTextPrimary,
    textSecondary: UamColors.lightTextSecondary,
    textTertiary: UamColors.lightTextTertiary,
    accent: UamColors.lightAccent,
    accentDark: UamColors.lightAccentDark,
    success: UamColors.lightSuccess,
    warning: UamColors.lightWarning,
    error: UamColors.lightError,
    planned: UamColors.lightPlanned,
    destructiveText: UamColors.lightError,
    onAccent: Color(0xFFFFFFFF),
    insetPanel: UamColors.lightInsetPanel,
    curveBackground: UamColors.lightCurveBackground,
    toggleOff: UamColors.lightToggleOff,
    toggleOffThumb: UamColors.lightToggleOffThumb,
    equalizerTrack: UamColors.lightEqualizerTrack,
    equalizerZeroLine: UamColors.lightEqualizerZeroLine,
    coreStatusWell: UamColors.lightCoreStatusWell,
    infoOverlay: Color(0x141687C4),
    successOverlay: Color(0x14147A54),
    warningOverlay: Color(0x148A5A0A),
    errorOverlay: Color(0x14B3262E),
    plannedOverlay: Color(0x146650C7),
    scrim: Color(0x66000000),
    modalShadow: Color(0x33000000),
    isDark: false,
  );

  final Color canvas;
  final Color canvasSecondary;
  final Color surface;
  final Color surfaceSecondary;
  final Color surfaceElevated;
  final Color border;
  final Color borderEmphasis;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentDark;
  final Color success;
  final Color warning;
  final Color error;
  final Color planned;
  final Color destructiveText;
  final Color onAccent;
  final Color insetPanel;
  final Color curveBackground;
  final Color toggleOff;
  final Color toggleOffThumb;
  final Color equalizerTrack;
  final Color equalizerZeroLine;
  final Color coreStatusWell;
  final Color infoOverlay;
  final Color successOverlay;
  final Color warningOverlay;
  final Color errorOverlay;
  final Color plannedOverlay;
  final Color scrim;
  final Color modalShadow;
  final bool isDark;

  /// Colour used for a semantic state, including the neutral fallback.
  Color statusColor(UamStatusTone tone) => switch (tone) {
    UamStatusTone.success => success,
    UamStatusTone.warning => warning,
    UamStatusTone.error => error,
    UamStatusTone.info => accent,
    UamStatusTone.planned => planned,
    UamStatusTone.muted => textTertiary,
  };

  @override
  UamColorTokens copyWith({
    Color? canvas,
    Color? canvasSecondary,
    Color? surface,
    Color? surfaceSecondary,
    Color? surfaceElevated,
    Color? border,
    Color? borderEmphasis,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentDark,
    Color? success,
    Color? warning,
    Color? error,
    Color? planned,
    Color? destructiveText,
    Color? onAccent,
    Color? insetPanel,
    Color? curveBackground,
    Color? toggleOff,
    Color? toggleOffThumb,
    Color? equalizerTrack,
    Color? equalizerZeroLine,
    Color? coreStatusWell,
    Color? infoOverlay,
    Color? successOverlay,
    Color? warningOverlay,
    Color? errorOverlay,
    Color? plannedOverlay,
    Color? scrim,
    Color? modalShadow,
    bool? isDark,
  }) {
    return UamColorTokens(
      canvas: canvas ?? this.canvas,
      canvasSecondary: canvasSecondary ?? this.canvasSecondary,
      surface: surface ?? this.surface,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      border: border ?? this.border,
      borderEmphasis: borderEmphasis ?? this.borderEmphasis,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentDark: accentDark ?? this.accentDark,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      planned: planned ?? this.planned,
      destructiveText: destructiveText ?? this.destructiveText,
      onAccent: onAccent ?? this.onAccent,
      insetPanel: insetPanel ?? this.insetPanel,
      curveBackground: curveBackground ?? this.curveBackground,
      toggleOff: toggleOff ?? this.toggleOff,
      toggleOffThumb: toggleOffThumb ?? this.toggleOffThumb,
      equalizerTrack: equalizerTrack ?? this.equalizerTrack,
      equalizerZeroLine: equalizerZeroLine ?? this.equalizerZeroLine,
      coreStatusWell: coreStatusWell ?? this.coreStatusWell,
      infoOverlay: infoOverlay ?? this.infoOverlay,
      successOverlay: successOverlay ?? this.successOverlay,
      warningOverlay: warningOverlay ?? this.warningOverlay,
      errorOverlay: errorOverlay ?? this.errorOverlay,
      plannedOverlay: plannedOverlay ?? this.plannedOverlay,
      scrim: scrim ?? this.scrim,
      modalShadow: modalShadow ?? this.modalShadow,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  UamColorTokens lerp(ThemeExtension<UamColorTokens>? other, double t) {
    if (other is! UamColorTokens) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    return UamColorTokens(
      canvas: mix(canvas, other.canvas),
      canvasSecondary: mix(canvasSecondary, other.canvasSecondary),
      surface: mix(surface, other.surface),
      surfaceSecondary: mix(surfaceSecondary, other.surfaceSecondary),
      surfaceElevated: mix(surfaceElevated, other.surfaceElevated),
      border: mix(border, other.border),
      borderEmphasis: mix(borderEmphasis, other.borderEmphasis),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      accent: mix(accent, other.accent),
      accentDark: mix(accentDark, other.accentDark),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      error: mix(error, other.error),
      planned: mix(planned, other.planned),
      destructiveText: mix(destructiveText, other.destructiveText),
      onAccent: mix(onAccent, other.onAccent),
      insetPanel: mix(insetPanel, other.insetPanel),
      curveBackground: mix(curveBackground, other.curveBackground),
      toggleOff: mix(toggleOff, other.toggleOff),
      toggleOffThumb: mix(toggleOffThumb, other.toggleOffThumb),
      equalizerTrack: mix(equalizerTrack, other.equalizerTrack),
      equalizerZeroLine: mix(equalizerZeroLine, other.equalizerZeroLine),
      coreStatusWell: mix(coreStatusWell, other.coreStatusWell),
      infoOverlay: mix(infoOverlay, other.infoOverlay),
      successOverlay: mix(successOverlay, other.successOverlay),
      warningOverlay: mix(warningOverlay, other.warningOverlay),
      errorOverlay: mix(errorOverlay, other.errorOverlay),
      plannedOverlay: mix(plannedOverlay, other.plannedOverlay),
      scrim: mix(scrim, other.scrim),
      modalShadow: mix(modalShadow, other.modalShadow),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// Semantic tones shared by status dots, notices, and badges.
enum UamStatusTone { success, warning, error, info, planned, muted }
