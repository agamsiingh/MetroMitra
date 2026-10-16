import 'package:flutter/material.dart';

/// App colour tokens (docs/design-system.md). Line colours are *data* and never
/// live here.
abstract final class AppColors {
  static const primaryLight = Color(0xFF1E5BD8);
  static const primaryDark = Color(0xFF9DB8FF);
  static const secondaryLight = Color(0xFFF57C1F);
  static const secondaryDark = Color(0xFFFFB77C);
  static const surfaceLight = Color(0xFFFAFBFD);
  static const surfaceDark = Color(0xFF101318);
  static const surfaceContainerLight = Color(0xFFF0F2F7);
  static const surfaceContainerDark = Color(0xFF1A1E25);
}

/// 4-pt grid spacing and shape tokens.
abstract final class AppSpacing {
  static const double unit = 4;
  static const double screenPadding = 16;
  static const double sectionGap = 24;
  static const double cardRadius = 16;
  static const double buttonRadius = 28;
}

/// Motion token: 200 ms standard easing; zero when animations are disabled.
abstract final class AppMotion {
  static const Duration standard = Duration(milliseconds: 200);
  static const Curve curve = Curves.easeInOut;
}

/// Semantic status colours not provided by Material 3 (success, warning).
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({required this.success, required this.warning});

  static const light = StatusColors(
    success: Color(0xFF1B7F3B),
    warning: Color(0xFF8A5A00),
  );
  static const dark = StatusColors(
    success: Color(0xFF7FD99A),
    warning: Color(0xFFFFC857),
  );

  final Color success;
  final Color warning;

  @override
  StatusColors copyWith({Color? success, Color? warning}) => StatusColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
  );

  @override
  StatusColors lerp(StatusColors? other, double t) => other == null
      ? this
      : StatusColors(
          success: Color.lerp(success, other.success, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
        );
}
