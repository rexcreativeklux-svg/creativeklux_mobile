import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Material theme built from [AppColors]. Inter everywhere, like the web app
/// (loaded in `src/app/layout.js`).
class AppTheme {
  AppTheme._();

  static ThemeData light([AppColors? colors]) => _build(Brightness.light, colors ?? AppColors.light);
  static ThemeData dark([AppColors? colors]) => _build(Brightness.dark, colors ?? AppColors.dark);

  /// Material's default scale (16px body, 22px titles, 24px dialog headings)
  /// reads like a website on a phone. This is the denser scale native apps
  /// use; anything that doesn't set its own size (list tiles, dialogs, menus,
  /// text fields, buttons) picks it up.
  static TextTheme _compact(TextTheme t) => t.copyWith(
    displayLarge: t.displayLarge?.copyWith(fontSize: 44),
    displayMedium: t.displayMedium?.copyWith(fontSize: 36),
    displaySmall: t.displaySmall?.copyWith(fontSize: 30),
    headlineLarge: t.headlineLarge?.copyWith(fontSize: 26),
    headlineMedium: t.headlineMedium?.copyWith(fontSize: 22),
    headlineSmall: t.headlineSmall?.copyWith(fontSize: 19),
    titleLarge: t.titleLarge?.copyWith(fontSize: 17),
    titleMedium: t.titleMedium?.copyWith(fontSize: 14.5),
    titleSmall: t.titleSmall?.copyWith(fontSize: 13),
    bodyLarge: t.bodyLarge?.copyWith(fontSize: 14.5),
    bodyMedium: t.bodyMedium?.copyWith(fontSize: 13.5),
    bodySmall: t.bodySmall?.copyWith(fontSize: 12),
    labelLarge: t.labelLarge?.copyWith(fontSize: 13.5),
    labelMedium: t.labelMedium?.copyWith(fontSize: 12),
    labelSmall: t.labelSmall?.copyWith(fontSize: 10.5),
  );

  static ThemeData _build(Brightness brightness, AppColors c) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(_compact(base.textTheme))
        .apply(bodyColor: c.gray900, displayColor: c.gray900);

    // Things that float OVER content (sheets, dialogs, menus, the drawer) stay
    // solid. A skin's surface is slightly translucent so its art shows behind
    // the app's bars and cards; over a page full of text that same 6% lets the
    // text underneath ghost through and fight the sheet's own.
    final floating = c.surface.withValues(alpha: 1);

    return base.copyWith(
      extensions: [c],
      scaffoldBackgroundColor: c.page,
      canvasColor: floating,
      dividerColor: c.gray200,
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.blue600,
        brightness: brightness,
        primary: AppColors.blue600,
        surface: c.surface,
        error: AppColors.red500,
      ),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.gray900,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: DividerThemeData(color: c.gray200, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: floating,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.gray300,
        dragHandleSize: const Size(32, 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: floating,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: c.gray600, height: 1.45),
      ),
      iconTheme: IconThemeData(size: 20, color: c.gray700),
      listTileTheme: ListTileThemeData(
        minTileHeight: 44,
        minVerticalPadding: 6,
        horizontalTitleGap: 12,
        iconColor: c.gray600,
        titleTextStyle: textTheme.bodyLarge?.copyWith(fontSize: 14, color: c.gray900),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: c.gray500),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: floating,
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyMedium?.copyWith(color: c.gray800),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        isDense: true,
        hintStyle: TextStyle(color: c.gray400, fontSize: 13.5),
      ),
      chipTheme: ChipThemeData(labelStyle: textTheme.labelMedium?.copyWith(fontSize: 12.5)),
      tooltipTheme: const TooltipThemeData(textStyle: TextStyle(fontSize: 12, color: Colors.white)),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.2),
        selectionHandleColor: AppColors.primary,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
