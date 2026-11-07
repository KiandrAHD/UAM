import 'package:flutter/material.dart';

import '../tokens/uam_colors.dart';
import '../tokens/uam_radii.dart';
import '../tokens/uam_shadows.dart';
import '../tokens/uam_spacing.dart';
import '../tokens/uam_typography.dart';

/// Builds the Material 3 themes used by the UAM application shell.
abstract final class UamTheme {
  static ThemeData get dark =>
      _build(brightness: Brightness.dark, tokens: UamColorTokens.dark);

  static ThemeData get light =>
      _build(brightness: Brightness.light, tokens: UamColorTokens.light);

  static ThemeData _build({
    required Brightness brightness,
    required UamColorTokens tokens,
  }) {
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: tokens.accent,
      onPrimary: tokens.onAccent,
      primaryContainer: tokens.surfaceElevated,
      onPrimaryContainer: tokens.textPrimary,
      secondary: tokens.accentDark,
      onSecondary: Colors.white,
      secondaryContainer: tokens.surfaceSecondary,
      onSecondaryContainer: tokens.textPrimary,
      tertiary: tokens.planned,
      onTertiary: tokens.isDark ? const Color(0xFF0B1018) : Colors.white,
      error: tokens.error,
      onError: colorsOn(tokens.error),
      surface: tokens.surface,
      onSurface: tokens.textPrimary,
      surfaceContainerHighest: tokens.surfaceElevated,
      onSurfaceVariant: tokens.textSecondary,
      outline: tokens.border,
      outlineVariant: tokens.borderEmphasis,
      shadow: tokens.modalShadow,
      scrim: tokens.scrim,
      inverseSurface: tokens.textPrimary,
      onInverseSurface: tokens.canvas,
      inversePrimary: tokens.accentDark,
    );

    final TextTheme textTheme = UamTypography.textTheme(
      brightness,
      tokens.textPrimary,
      tokens.textSecondary,
      tokens.textTertiary,
    );

    final RoundedRectangleBorder cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(UamRadii.card),
      side: BorderSide(color: tokens.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.canvas,
      canvasColor: tokens.canvasSecondary,
      dividerColor: tokens.border,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[tokens],
      cardTheme: CardThemeData(
        color: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: cardShape,
      ),
      dividerTheme: DividerThemeData(
        color: tokens.border,
        space: 1,
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.canvas,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.accent,
          foregroundColor: tokens.onAccent,
          disabledBackgroundColor: tokens.surfaceElevated,
          disabledForegroundColor: tokens.textTertiary,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(UamRadii.control),
          ),
          textStyle: UamTypography.button,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          disabledForegroundColor: tokens.textTertiary,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          side: BorderSide(color: tokens.borderEmphasis),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(UamRadii.control),
          ),
          textStyle: UamTypography.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.accent,
          disabledForegroundColor: tokens.textTertiary,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(UamRadii.control),
          ),
          textStyle: UamTypography.button,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.textSecondary,
          disabledForegroundColor: tokens.textTertiary,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(UamRadii.control),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.insetPanel,
        hintStyle: UamTypography.body.copyWith(color: tokens.textTertiary),
        labelStyle: UamTypography.description.copyWith(
          color: tokens.textSecondary,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: UamSpacing.lg,
          vertical: UamSpacing.mdPlus,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UamRadii.control),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UamRadii.control),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UamRadii.control),
          borderSide: BorderSide(color: tokens.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UamRadii.control),
          borderSide: BorderSide(color: tokens.error),
        ),
        errorStyle: UamTypography.micro.copyWith(color: tokens.error),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: tokens.accent,
        inactiveTrackColor: tokens.equalizerTrack,
        thumbColor: tokens.accent,
        overlayColor: tokens.accent.withValues(alpha: 0.16),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return tokens.toggleOffThumb;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return tokens.toggleOff.withValues(alpha: 0.6);
          }
          if (states.contains(WidgetState.selected)) {
            return tokens.accentDark;
          }
          return tokens.toggleOff;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : tokens.borderEmphasis,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UamRadii.modal),
          side: BorderSide(color: tokens.borderEmphasis),
        ),
        titleTextStyle: UamTypography.sectionTitle.copyWith(
          color: tokens.textPrimary,
        ),
        contentTextStyle: UamTypography.body.copyWith(
          color: tokens.textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: tokens.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(UamRadii.modal),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(UamRadii.badge),
          border: Border.all(color: tokens.borderEmphasis),
        ),
        textStyle: UamTypography.micro.copyWith(color: tokens.textPrimary),
        waitDuration: const Duration(milliseconds: 350),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.accent,
        linearTrackColor: tokens.equalizerTrack,
        circularTrackColor: tokens.equalizerTrack,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.surfaceElevated,
        contentTextStyle: UamTypography.body.copyWith(
          color: tokens.textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UamRadii.notice),
          side: BorderSide(color: tokens.borderEmphasis),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: tokens.textSecondary,
        textColor: tokens.textPrimary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: UamSpacing.lg,
          vertical: UamSpacing.xs,
        ),
      ),
      shadowColor: tokens.modalShadow,
      focusColor: tokens.accent.withValues(alpha: 0.22),
      hoverColor: tokens.surfaceSecondary.withValues(alpha: 0.55),
      highlightColor: tokens.accent.withValues(alpha: 0.10),
    );
  }

  static Color colorsOn(Color background) {
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : const Color(0xFF081018);
  }
}

/// Convenience accessors for UAM tokens and semantic roles.
extension UamThemeContext on BuildContext {
  UamColorTokens get uamColors =>
      Theme.of(this).extension<UamColorTokens>() ?? UamColorTokens.dark;

  bool get uamIsCompact => MediaQuery.sizeOf(this).width <= 390;

  TextTheme get uamText => Theme.of(this).textTheme;

  Color get uamCanvas => uamColors.canvas;
}

/// Compatibility alias so existing imports of `AppTheme` keep working.
abstract final class AppTheme {
  static ThemeData get light => UamTheme.light;
  static ThemeData get dark => UamTheme.dark;
}

/// A subtle radial atmosphere used behind the desktop canvas.
class UamAtmosphere extends StatelessWidget {
  const UamAtmosphere({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.uamColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.canvas,
        gradient: RadialGradient(
          center: const Alignment(0.25, -0.95),
          radius: 1.15,
          colors: <Color>[
            tokens.accent.withValues(alpha: tokens.isDark ? 0.10 : 0.06),
            tokens.canvas.withValues(alpha: 0),
          ],
        ),
      ),
      child: child,
    );
  }
}

/// Shared shadow constants are re-exported for feature widgets.
abstract final class UamElevation {
  static List<BoxShadow> get modal => UamShadows.modal;
}
