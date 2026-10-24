import 'package:flutter/material.dart';

/// The web app's palette (Tailwind v4 defaults + the `.dark` overrides in
/// `src/app/globals.css`), exposed as a ThemeExtension so widgets can write
/// `context.colors.gray500` the same way the web writes `text-gray-500`.
///
/// Like the web, dark mode re-points the gray ramp (900 becomes the lightest)
/// rather than defining separate "dark" names — so a widget styled once with
/// gray tokens flips correctly in both themes.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.page,
    required this.surface,
    required this.gray50,
    required this.gray100,
    required this.gray200,
    required this.gray300,
    required this.gray400,
    required this.gray500,
    required this.gray600,
    required this.gray700,
    required this.gray800,
    required this.gray900,
    required this.blueTint,
    required this.redTint,
  });

  /// Main content background (`bg-page`).
  final Color page;

  /// Cards, panels, bars (`bg-surface`).
  final Color surface;

  final Color gray50;
  final Color gray100;
  final Color gray200;
  final Color gray300;
  final Color gray400;
  final Color gray500;
  final Color gray600;
  final Color gray700;
  final Color gray800;
  final Color gray900;

  /// Active nav item background (`bg-blue-50`).
  final Color blueTint;

  /// Destructive-action background (`bg-red-50` / `bg-red-100`).
  final Color redTint;

  // ── Fixed brand colours — identical in both themes, as on the web ──────────

  /// Auth screens' primary (`#1447e6`).
  static const primary = Color(0xFF1447E6);
  static const primaryHover = Color(0xFF0F3BBF);

  /// App chrome blue (`blue-600` / `#155dfc`) — the ACTION colour.
  ///
  /// Not const: a skin re-points it, like skins.css re-points
  /// `--color-blue-600` (see core/theme/skins.dart). Set through
  /// [applyAccent]; the app rebuilds every widget after a change.
  static Color get blue600 => _accent;
  static Color get blue500 => _accentSoft;

  static const _defaultBlue600 = Color(0xFF155DFC);
  static const _defaultBlue500 = Color(0xFF2B7FFF);
  static Color _accent = _defaultBlue600;
  static Color _accentSoft = _defaultBlue500;

  /// A skin's accent, or the app blue when [accent] is null.
  static void applyAccent({Color? accent, Color? soft}) {
    _accent = accent ?? _defaultBlue600;
    _accentSoft = soft ?? _defaultBlue500;
  }

  static const red500 = Color(0xFFFB2C36);
  static const red600 = Color(0xFFE7000B);

  /// The studio results' "selected" / "ready" green (`#22c55e` on the web).
  static const green500 = Color(0xFF22C55E);
  static const green600 = Color(0xFF00A63E);
  static const amber500 = Color(0xFFFE9A00);
  static const violet600 = Color(0xFF7F22FE);

  /// Fallback brand colour when a brand has no valid `primary_color`.
  static const brandFallback = Color(0xFF1E3A8A);

  static const light = AppColors(
    page: Color(0xFFF7F8FC),
    surface: Color(0xFFFFFFFF),
    gray50: Color(0xFFF9FAFB),
    gray100: Color(0xFFF3F4F6),
    gray200: Color(0xFFE5E7EB),
    gray300: Color(0xFFD1D5DC),
    gray400: Color(0xFF99A1AF),
    gray500: Color(0xFF6A7282),
    gray600: Color(0xFF4A5565),
    gray700: Color(0xFF364153),
    gray800: Color(0xFF1E2939),
    gray900: Color(0xFF101828),
    blueTint: Color(0xFFEFF6FF),
    redTint: Color(0xFFFEF2F2),
  );

  static const dark = AppColors(
    page: Color(0xFF0E0E11),
    surface: Color(0xFF1C1C20),
    gray50: Color(0xFF0E0E11),
    gray100: Color(0xFF18181B),
    gray200: Color(0xFF2A2A30),
    gray300: Color(0xFF3A3A42),
    gray400: Color(0xFF6B6B75),
    gray500: Color(0xFF9B9BA5),
    gray600: Color(0xFFBABAC2),
    gray700: Color(0xFFD2D2D8),
    gray800: Color(0xFFE6E6EA),
    gray900: Color(0xFFF5F5F7),
    blueTint: Color(0x26155DFC),
    redTint: Color(0x26FB2C36),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) => t < 0.5 || other == null ? this : other;
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
