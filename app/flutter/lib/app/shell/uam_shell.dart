import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../design_system/theme/uam_theme.dart';
import '../../design_system/tokens/uam_breakpoints.dart';
import '../../design_system/tokens/uam_spacing.dart';
import '../router/app_router.dart';
import '../router/app_routes.dart';
import 'uam_mobile_navigation.dart';
import 'uam_sidebar.dart';
import 'uam_top_bar.dart';

/// Responsive application shell shared by every Phase 1 module.
final class UamShell extends StatefulWidget {
  const UamShell({required this.route, super.key});

  final String route;

  @override
  State<UamShell> createState() => _UamShellState();
}

final class _UamShellState extends State<UamShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${AppRoutes.labelFor(widget.route)} page',
        Directionality.of(context),
      );
    });
  }

  void _navigate(String route) {
    if (route == widget.route) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widthClass = uamWidthClassFor(constraints.maxWidth);
        final mobile = uamUsesMobileNavigation(widthClass);
        return Scaffold(
          body: UamAtmosphere(
            child: SafeArea(
              bottom: false,
              child: mobile
                  ? _MobileShell(
                      route: widget.route,
                      widthClass: widthClass,
                      onNavigate: _navigate,
                    )
                  : _DesktopShell(
                      route: widget.route,
                      widthClass: widthClass,
                      onNavigate: _navigate,
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.route,
    required this.widthClass,
    required this.onNavigate,
  });

  final String route;
  final UamWidthClass widthClass;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        UamSidebar(
          route: route,
          widthClass: widthClass,
          onNavigate: onNavigate,
        ),
        Expanded(
          child: Column(
            children: <Widget>[
              UamTopBar(
                route: route,
                widthClass: widthClass,
                onNavigate: onNavigate,
              ),
              Expanded(
                child: _ContentWorkspace(route: route, widthClass: widthClass),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.route,
    required this.widthClass,
    required this.onNavigate,
  });

  final String route;
  final UamWidthClass widthClass;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        UamTopBar(route: route, widthClass: widthClass, onNavigate: onNavigate),
        Expanded(
          child: _ContentWorkspace(route: route, widthClass: widthClass),
        ),
        UamMobileNavigation(route: route, onNavigate: onNavigate),
      ],
    );
  }
}

class _ContentWorkspace extends StatelessWidget {
  const _ContentWorkspace({required this.route, required this.widthClass});

  final String route;
  final UamWidthClass widthClass;

  @override
  Widget build(BuildContext context) {
    final mobile = uamUsesMobileNavigation(widthClass);
    final compact = widthClass == UamWidthClass.compact;
    final padding = EdgeInsets.fromLTRB(
      compact ? 15 : (mobile ? 15 : UamSpacing.pageWide),
      mobile ? UamSpacing.huge : UamSpacing.page,
      compact ? 15 : (mobile ? 15 : UamSpacing.pageWide),
      mobile ? UamSpacing.mobileBottom : UamSpacing.desktopBottom,
    );
    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: UamBreakpoints.contentMax,
          ),
          child: AppRouter.pageFor(route),
        ),
      ),
    );
  }
}
