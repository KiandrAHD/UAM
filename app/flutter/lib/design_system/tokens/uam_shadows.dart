import 'package:flutter/material.dart';

/// Central shadow values. Glows are semantic, not decorative.
abstract final class UamShadows {
  static const List<BoxShadow> brandGlow = <BoxShadow>[
    BoxShadow(color: Color(0x332CBFF3), blurRadius: 26),
  ];

  static const List<BoxShadow> activeIndicator = <BoxShadow>[
    BoxShadow(color: Color(0xFF2CBFF3), blurRadius: 12),
  ];

  static const List<BoxShadow> connectedDot = <BoxShadow>[
    BoxShadow(color: Color(0x6645D8A0), blurRadius: 8),
  ];

  static const List<BoxShadow> primaryButton = <BoxShadow>[
    BoxShadow(color: Color(0x2E168BD4), blurRadius: 24, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> modal = <BoxShadow>[
    BoxShadow(color: Color(0xFF000000), blurRadius: 100, offset: Offset(0, 30)),
  ];

  static const List<BoxShadow> mobileSheet = <BoxShadow>[
    BoxShadow(color: Color(0x73000000), blurRadius: 50, offset: Offset(0, -15)),
  ];
}
