import 'package:flutter/material.dart';

/// Design tokens, registered as a theme extension so a snapshot can name the
/// token behind a resolved colour.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brandAccent,
    required this.surface,
    required this.surfaceMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.positive,
    required this.negative,
    required this.divider,
  });

  final Color brandAccent;
  final Color surface;
  final Color surfaceMuted;
  final Color textPrimary;
  final Color textSecondary;
  final Color positive;
  final Color negative;
  final Color divider;

  static const AppTokens light = AppTokens(
    brandAccent: Color(0xFF3949AB),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1F3F8),
    textPrimary: Color(0xFF1B1D24),
    textSecondary: Color(0xFF5C6070),
    positive: Color(0xFF1E8E3E),
    negative: Color(0xFFD93025),
    divider: Color(0xFFE1E4EC),
  );

  static const AppTokens dark = AppTokens(
    brandAccent: Color(0xFF8C9EFF),
    surface: Color(0xFF121318),
    surfaceMuted: Color(0xFF1E2028),
    textPrimary: Color(0xFFF2F3F7),
    textSecondary: Color(0xFFA9ADBC),
    positive: Color(0xFF81C995),
    negative: Color(0xFFF28B82),
    divider: Color(0xFF2E313B),
  );

  Map<String, Color> get named => <String, Color>{
    'brand.accent': brandAccent,
    'surface': surface,
    'surface.muted': surfaceMuted,
    'text.primary': textPrimary,
    'text.secondary': textSecondary,
    'positive': positive,
    'negative': negative,
    'divider': divider,
  };

  static AppTokens of(BuildContext context) => Theme.of(context).extension<AppTokens>()!;

  @override
  AppTokens copyWith({Color? brandAccent}) => AppTokens(
    brandAccent: brandAccent ?? this.brandAccent,
    surface: surface,
    surfaceMuted: surfaceMuted,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    positive: positive,
    negative: negative,
    divider: divider,
  );

  @override
  AppTokens lerp(AppTokens? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// Spacing scale.
abstract final class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
}

ThemeData appTheme(Brightness brightness, {AppTokens? tokens}) {
  final AppTokens t = tokens ?? (brightness == Brightness.light ? AppTokens.light : AppTokens.dark);
  return ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(seedColor: t.brandAccent, brightness: brightness),
    scaffoldBackgroundColor: t.surface,
    dividerColor: t.divider,
    extensions: <ThemeExtension<dynamic>>[t],
  );
}
