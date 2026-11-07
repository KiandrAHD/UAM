import 'package:flutter/material.dart';

/// Semantic typography values for UAM.
///
/// The Figma prototype has no named type scale. These styles name the compact
/// roles that recur across the design instead of scaling every label to body
/// size.
abstract final class UamTypography {
  static const String fontFamily = 'Inter';
  static const List<String> fontFamilyFallback = <String>[
    'Segoe UI',
    'Roboto',
    'sans-serif',
  ];
  static const String monoFamily = 'monospace';

  /// Desktop page title, 28px, tight tracking.
  static const TextStyle pageTitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.98,
    height: 1.15,
  );

  /// Mobile page title, 24px.
  static const TextStyle pageTitleMobile = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.84,
    height: 1.15,
  );

  /// Large device title.
  static const TextStyle deviceTitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.44,
  );

  /// Brand wordmark.
  static const TextStyle brand = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.44,
  );

  /// Major status or section headline.
  static const TextStyle majorStatus = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  /// Section title.
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
  );

  /// Card title.
  static const TextStyle cardTitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
  );

  /// Body baseline.
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// Button label.
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  /// Navigation and compact control label.
  static const TextStyle navigation = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  /// Supporting copy.
  static const TextStyle description = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// Page eyebrow.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.62,
    height: 1.2,
  );

  /// Technical category label.
  static const TextStyle technicalLabel = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.08,
    height: 1.2,
  );

  /// Badge and status label.
  static const TextStyle badge = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 8,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    height: 1.2,
  );

  /// Microcopy.
  static const TextStyle micro = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// Tabular numeric value.
  static const TextStyle numeric = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Technical identifier or timestamp.
  static const TextStyle monospace = TextStyle(
    fontFamily: monoFamily,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// Material text theme assembled from the semantic styles.
  static TextTheme textTheme(
    Brightness brightness,
    Color primary,
    Color secondary,
    Color tertiary,
  ) {
    final Color strong = primary;
    return TextTheme(
      displayLarge: pageTitle.copyWith(color: strong),
      displayMedium: pageTitle.copyWith(color: strong),
      displaySmall: pageTitleMobile.copyWith(color: strong),
      headlineLarge: pageTitleMobile.copyWith(color: strong),
      headlineMedium: majorStatus.copyWith(color: strong),
      headlineSmall: majorStatus.copyWith(color: strong),
      titleLarge: deviceTitle.copyWith(color: strong),
      titleMedium: sectionTitle.copyWith(color: strong),
      titleSmall: cardTitle.copyWith(color: strong),
      bodyLarge: body.copyWith(color: strong),
      bodyMedium: body.copyWith(color: secondary),
      bodySmall: description.copyWith(color: tertiary),
      labelLarge: button.copyWith(color: strong),
      labelMedium: navigation.copyWith(color: secondary),
      labelSmall: technicalLabel.copyWith(color: tertiary),
    );
  }
}
