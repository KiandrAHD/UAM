import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uam/app/shell/uam_mobile_navigation.dart';
import 'package:uam/app/shell/uam_sidebar.dart';
import 'package:uam/app/shell/uam_top_bar.dart';

import '../support/test_harness.dart';

void main() {
  group('responsive shell', () {
    testWidgets('compact width uses mobile navigation without a sidebar', (
      tester,
    ) async {
      await pumpUamApp(tester, size: const Size(360, 800));

      expect(find.byType(UamMobileNavigation), findsOneWidget);
      expect(find.byKey(const Key('uam-mobile-nav')), findsOneWidget);
      expect(find.byType(UamSidebar), findsNothing);
      expect(tester.getSize(find.byType(UamTopBar)).height, 60);
    });

    testWidgets('mobile width uses mobile navigation', (tester) async {
      await pumpUamApp(tester, size: const Size(600, 800));

      expect(find.byKey(const Key('uam-mobile-nav')), findsOneWidget);
      expect(find.byType(UamSidebar), findsNothing);
      expect(tester.getSize(find.byType(UamTopBar)).height, 60);
    });

    testWidgets('tablet width uses a 76px icon sidebar', (tester) async {
      await pumpUamApp(tester, size: const Size(900, 900));

      expect(find.byType(UamSidebar), findsOneWidget);
      expect(find.byKey(const Key('uam-mobile-nav')), findsNothing);
      expect(tester.getSize(find.byKey(const Key('uam-sidebar'))).width, 76);
      expect(tester.getSize(find.byType(UamTopBar)).height, 78);
    });

    testWidgets('desktop width uses a 238px sidebar', (tester) async {
      await pumpUamApp(tester, size: const Size(1400, 1000));

      expect(find.byType(UamSidebar), findsOneWidget);
      expect(find.byKey(const Key('uam-mobile-nav')), findsNothing);
      expect(tester.getSize(find.byKey(const Key('uam-sidebar'))).width, 238);
      expect(tester.getSize(find.byType(UamTopBar)).height, 78);
    });
  });
}
