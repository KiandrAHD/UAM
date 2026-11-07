/// Application theme facade.
///
/// The actual tokens and Material theme live in `design_system/`; this file
/// keeps the Phase 0 import path stable for existing callers.
library;

export '../../design_system/theme/uam_theme.dart'
    show AppTheme, UamAtmosphere, UamElevation, UamTheme, UamThemeContext;
