import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uam/design_system/theme/uam_theme.dart';
import 'package:uam/design_system/tokens/uam_breakpoints.dart';
import 'package:uam/design_system/tokens/uam_colors.dart';
import 'package:uam/design_system/tokens/uam_radii.dart';
import 'package:uam/design_system/tokens/uam_spacing.dart';
import 'package:uam/design_system/tokens/uam_typography.dart';

void main() {
  group('design tokens', () {
    test('dark palette matches the documented Figma values', () {
      expect(UamColors.background, const Color(0xFF080C12));
      expect(UamColors.surface, const Color(0xFF111720));
      expect(UamColors.accent, const Color(0xFF2CBFF3));
      expect(UamColors.success, const Color(0xFF45D8A0));
      expect(UamColorTokens.dark.canvas, UamColors.background);
      expect(UamColorTokens.dark.isDark, isTrue);
    });

    test('light palette is a distinct, documented derivative', () {
      expect(UamColorTokens.light.isDark, isFalse);
      expect(UamColorTokens.light.canvas, isNot(UamColorTokens.dark.canvas));
      expect(UamColorTokens.light.accent, UamColors.lightAccent);
    });

    test('semantic status colours resolve for both themes', () {
      for (final tokens in <UamColorTokens>[
        UamColorTokens.dark,
        UamColorTokens.light,
      ]) {
        expect(tokens.statusColor(UamStatusTone.success), tokens.success);
        expect(tokens.statusColor(UamStatusTone.error), tokens.error);
        expect(tokens.statusColor(UamStatusTone.planned), tokens.planned);
      }
    });

    test('structural breakpoints match the specification', () {
      expect(UamBreakpoints.compact, 390);
      expect(UamBreakpoints.mobile, 760);
      expect(UamBreakpoints.tablet, 1100);
      expect(UamBreakpoints.sidebarDesktop, 238);
      expect(UamBreakpoints.sidebarTablet, 76);
      expect(UamBreakpoints.topBarDesktop, 78);
      expect(UamBreakpoints.topBarMobile, 60);
      expect(UamBreakpoints.bottomNavigation, 70);
      expect(UamBreakpoints.contentMax, 1500);
    });

    test('width classes follow the documented thresholds', () {
      expect(uamWidthClassFor(390), UamWidthClass.compact);
      expect(uamWidthClassFor(760), UamWidthClass.mobile);
      expect(uamWidthClassFor(1100), UamWidthClass.tablet);
      expect(uamWidthClassFor(1101), UamWidthClass.desktop);
      expect(uamUsesSidebar(UamWidthClass.tablet), isTrue);
      expect(uamUsesMobileNavigation(UamWidthClass.mobile), isTrue);
    });

    test('spacing and radii expose the observed rhythm', () {
      expect(UamSpacing.xs, 4);
      expect(UamSpacing.lg, 12);
      expect(UamSpacing.xl, 16);
      expect(UamSpacing.pageWide, 34);
      expect(UamSpacing.mobileBottom, 94);
      expect(UamRadii.badge, 5);
      expect(UamRadii.card, 14);
      expect(UamRadii.modal, 16);
    });

    test('typography uses Inter with the documented page-title scale', () {
      expect(UamTypography.fontFamily, 'Inter');
      expect(UamTypography.pageTitle.fontSize, 28);
      expect(UamTypography.pageTitleMobile.fontSize, 24);
      expect(UamTypography.eyebrow.fontSize, 9);
    });
  });

  group('themes', () {
    test('dark and light ThemeData embed the token extension', () {
      final dark = UamTheme.dark;
      final light = UamTheme.light;
      expect(dark.brightness, Brightness.dark);
      expect(light.brightness, Brightness.light);
      expect(dark.extension<UamColorTokens>(), UamColorTokens.dark);
      expect(light.extension<UamColorTokens>(), UamColorTokens.light);
      expect(dark.scaffoldBackgroundColor, UamColors.background);
      expect(light.scaffoldBackgroundColor, UamColors.lightBackground);
    });

    test('theme extension lerp produces an interpolated palette', () {
      final mid = UamColorTokens.dark.lerp(UamColorTokens.light, 0.5);
      expect(mid, isA<UamColorTokens>());
      expect(mid.canvas, isNot(UamColorTokens.dark.canvas));
      expect(mid.canvas, isNot(UamColorTokens.light.canvas));
    });
  });
}
